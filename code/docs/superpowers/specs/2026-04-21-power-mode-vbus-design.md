# Power Mode VBUS Design

## Goal

Add runtime USB-versus-battery power-mode switching based on `GPIO21`, then use that mode to control:

- USB always-on profile
- battery low-power profile
- pre-wakeup timing before the next battery collection cycle
- safe fallbacks when VBUS or low-power control fails

This design builds on the existing filtered collection pipeline, alarm flow, and door-edge event flow. It does not add new cloud command behavior.

## Hardware Assumption

The user confirmed this wiring rule:

- `GPIO21` is connected to Type-C `VBUS` through a pull-down detection circuit
- `GPIO21 == high` means USB/VBUS is present
- `GPIO21 == low` means no USB/VBUS, so the device is battery powered

Software therefore treats `GPIO21` as the only mode-selection signal.

## Scope

### Included

- `GPIO21` VBUS detection in the GPIO layer
- one application power module that exposes current mode and mode profile
- USB profile: `10s` sample / `10s` report / no sleep
- battery profile: `60s` sample / `60s` report / pre-wakeup `5s` before the next full cycle
- battery-mode post-cycle sleep decision
- Chinese runtime logs for mode detection, wakeup scheduling, and sleep fallback

### Excluded

- BQ25616 `CE` / `PG` / `STAT` integration
- cloud-triggered mode changes
- cloud-triggered immediate collect/report commands
- long-lived PM state persistence

## Configuration Model

Keep `config.lua` as the only runtime configuration definition entrypoint.

Add these runtime fields:

```lua
usb_sample_interval_ms = 10000,
usb_report_interval_ms = 10000,
battery_sample_interval_ms = 60000,
battery_report_interval_ms = 60000,
battery_prewake_ms = 5000
```

These fields are mutable and persist through `app_config`.

The existing generic `sample_interval_ms` / `report_interval_ms` fields become obsolete in the application flow and should no longer drive scheduling once the power-mode layer is enabled.

## Architecture

### `ggpio.lua`

Add one new GPIO input capability:

- define `GPIO21_VBUS = 21`
- configure it as an input reader
- expose `get_usb_power_state()`

Return rules:

- `true` when the `GPIO21` reader returns high
- `false` when it returns low
- `nil` when the reader is unavailable

### `app_power.lua`

Create a dedicated module for runtime power-mode decisions. It should not know collection, alarm, or MQTT details.

Proposed API:

```lua
local mode = app_power.current_mode(cfg)
local profile = app_power.current_profile(cfg)
local should_sleep = app_power.should_sleep_after_cycle(cfg)
local ok = app_power.prepare_next_wakeup(cfg)
local ok = app_power.enter_sleep()
```

Mode values:

- `"USB"`
- `"BATTERY"`

Fallback rule:

- if VBUS detection fails, return `"USB"` and log a fallback reason

Profile shape:

```lua
{
  mode = "USB" or "BATTERY",
  sample_interval_ms = ...,
  report_interval_ms = ...,
  prewake_ms = ...
}
```

### `application.lua`

Keep one shared processing function for business work, but let scheduling depend on the current power profile.

Flow:

1. before each cycle, read the current power profile
2. run the shared processing flow:
   - collect raw snapshot
   - apply algorithm filtering
   - evaluate alarms
   - persist latest snapshot
   - send SMS if needed
   - publish to MQTT if due
3. after the cycle:
   - if mode is `USB`, wait normally until the next cycle
   - if mode is `BATTERY`, configure next wakeup and try to enter sleep
4. on wakeup, re-evaluate `GPIO21` because the mode may have changed while sleeping

Door-edge events continue to use the existing immediate processing path. In battery mode, that path must not create a second overlapping cycle while a normal cycle is already running.

## Sleep And Wake Strategy

Battery mode needs both a full-cycle interval and a pre-wakeup lead time.

Definitions:

- full battery cycle interval = `battery_sample_interval_ms`
- pre-wakeup lead = `battery_prewake_ms`
- wakeup scheduling delay = `battery_sample_interval_ms - battery_prewake_ms`

Example:

- sample/report interval = `60000`
- prewake = `5000`
- schedule wakeup after `55000`
- on wakeup, allow the remaining `5000` for sensor power/network warm-up if needed

For this milestone, the simplest implementation is acceptable:

- schedule a wakeup at `interval - prewake`
- when awakened by the timer, wait the remaining `prewake` time in software before running the normal cycle if needed

This preserves the user-required “wake `5s` early” behavior even if the PM API is coarse.

## PM Boundary

Low-power API names must be verified against the actual LuatOS environment during implementation.

To keep the application boundary stable, isolate PM calls inside `app_power.lua`. The rest of the code should not call `pm.*` directly.

If PM control is unavailable or a PM API call fails:

- log the failure in Chinese
- skip sleep
- continue in always-on behavior for that cycle

## Error Handling

- VBUS read failure:
  - log `"VBUS检测失败，回退到USB模式"`
  - continue with USB profile

- wakeup scheduling failure:
  - log the failure
  - skip sleep for this cycle

- sleep entry failure:
  - log the failure
  - stay awake

- concurrent battery timer wake and door wake:
  - reuse the existing application processing lock
  - at most one business cycle may run at a time

## Testing

Add coverage for:

- `ggpio.lua` VBUS input initialization and level reads
- `app_power.lua` mode decision and profile generation
- fallback to USB mode on VBUS-read failure
- battery mode scheduling path in `application.lua`
- USB mode normal wait path in `application.lua`
- battery mode trying to schedule wakeup and enter sleep after a cycle
