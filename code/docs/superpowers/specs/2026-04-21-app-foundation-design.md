# Application Foundation Design

## Goal

Turn the current device test project into a first real application milestone with:

- a formal business entrypoint
- local configuration and latest-data persistence backed by `fskv`
- a unified collection pipeline that uses the existing sensor modules
- real MQTT data publication based on collected values instead of random demo data

This milestone deliberately excludes full alarm execution, SMS sending, power-mode switching, and low-power sleep orchestration.

## Context

The current repository already has reusable hardware-facing modules:

- `gadc.lua` for battery and ADC reads
- `gsht30.lua` for two SHT30 sensors
- `gbaro.lua` for two UART pressure sensors
- `glbs.lua` for cached AirLBS positioning
- `ggpio.lua` for controllable GPIO power rails and door wakeup input
- `iot.lua` / `gmqtt.lua` for cloud messaging

What is missing is the application layer. `main.lua` is still a sensor test script, `application.lua` is empty, there is no persisted runtime configuration, and the MQTT layer still publishes random values.

The approved first milestone is intentionally scoped to:

- switch `main.lua` to the formal business entrypoint
- persist runtime configuration and latest collected snapshot with `fskv`
- integrate existing sensor modules into one collection flow
- keep cloud parameter read/write working, but only for a small validated configuration whitelist

## Scope

### Included

- formal application startup flow
- runtime config defaults + `fskv` persistence
- latest snapshot persistence
- unified collection of battery, current ADC, door state, SHT30, pressure, and LBS
- MQTT publication of real snapshot data
- validated config updates from `dp/set`
- updated tests that match the new application shape

### Excluded

- SMS sending
- full alarm decision engine
- USB vs battery power-mode switching
- sleep / wake scheduling
- BQ25616 software control and PG/STAT/CE integration
- scoring system

## Architecture

Keep the existing hardware modules in place and add a thin application layer above them. This avoids unnecessary file moves while creating a stable business-oriented boundary for future alarm, power, and scheduling work.

### Files and Responsibilities

- `main.lua`
  - minimal boot file
  - requires shared modules
  - starts the formal application entrypoint

- `application.lua`
  - application coordinator
  - loads config
  - initializes hardware-facing modules
  - starts MQTT integration
  - schedules the unified collection and report loop

- `app_config.lua`
  - owns default runtime config
  - loads and saves config through `fskv`
  - validates cloud-updatable fields
  - exposes read/update helpers

- `app_state.lua`
  - holds the latest collected snapshot in memory
  - persists the latest snapshot through `fskv`
  - exposes read/write helpers for the rest of the app

- `app_collect.lua`
  - performs one collection cycle
  - reads all current sensor-facing modules
  - returns one normalized snapshot table
  - tolerates partial sensor failure

- `gmqtt.lua`
  - keeps transport and topic handling
  - stops generating random demo telemetry
  - publishes normalized snapshots supplied by the application layer
  - routes `dp/get` and `dp/set` through app config and app state helpers

- `config.lua`
  - remains for static factory defaults such as MQTT credentials, phone number, and default AirLBS credentials
  - no longer acts as the mutable runtime configuration store

## Runtime Configuration Model

`app_config.lua` owns the runtime configuration record. It is initialized from defaults and then overlaid with persisted values from `fskv`.

Initial runtime config fields:

```lua
{
    sample_interval_ms = 10000,
    report_interval_ms = 10000,
    airlbs_project_id = "",
    airlbs_project_key = "",
    airlbs_timeout = 10000,
    temp_low = -40,
    temp_high = 85,
    current_low = 0,
    current_high = 50000,
    pressure_diff_low = 1.0,
    pressure_diff_high = 1.5,
    door_open_warn_ms = 5000
}
```

The exact numeric defaults can be adjusted during implementation, but the field set is fixed for this milestone.

### Persistence Rules

- on boot, load persisted config from `fskv`
- if no valid persisted config exists, use defaults and save them
- cloud updates only apply to a validated whitelist
- successful cloud updates are immediately persisted

## Snapshot Model

`app_collect.collect_once()` returns one snapshot table. The snapshot is the common shape shared by the application loop, persistence layer, and MQTT reporting.

Suggested shape:

```lua
{
    timestamp = "2026-04-21 11:00:00",
    battery_mv = 3800,
    battery_percent = 56,
    current_raw = 1234,
    current_mv = 500,
    current_sensor_mv = 1000,
    door_open = false,
    location = { 31.1354542, 121.5423279 },
    temp_hum = {
        [0] = { ok = true, temperature = 25.2, humidity = 50.1 },
        [1] = { ok = true, temperature = 26.8, humidity = 60.3 }
    },
    pressure = {
        [1] = { ok = true, temperature = 25.8, pressure = 100.0 },
        [2] = { ok = true, temperature = 26.0, pressure = 101.2 }
    }
}
```

### Partial Failure Policy

This milestone uses degraded-but-running behavior:

- collection always returns a snapshot table
- a failing device contributes `{ ok = false, error = "..." }` where appropriate
- one failed device must not abort the rest of the collection cycle
- the latest snapshot can still be persisted and reported even when some fields failed

This keeps the device observable in the field instead of turning one sensor failure into a total telemetry outage.

## Application Flow

`application.start()` follows this order:

1. load runtime config from `app_config`
2. initialize GPIO and sensor modules
3. initialize `glbs` from runtime config
4. initialize and start MQTT transport
5. start one periodic task that:
   - collects one snapshot
   - saves it through `app_state`
   - publishes it when the report interval is due

For this milestone, the device runs in a single always-on mode with the configured intervals. USB/battery mode switching is deferred to a later design.

## MQTT Integration Boundary

`gmqtt.lua` remains the transport-facing module, but its responsibilities change.

### Telemetry

- remove random demo data generation
- accept a real snapshot from the application layer
- publish normalized fields derived from the snapshot

### Cloud Read/Write

`dp/get` should return:

- current runtime config fields
- latest snapshot summary when available

`dp/set` should only allow this whitelist:

- `sample_interval_ms`
- `report_interval_ms`
- `temp_low`
- `temp_high`
- `current_low`
- `current_high`
- `pressure_diff_low`
- `pressure_diff_high`
- `door_open_warn_ms`

Processing rules:

- reject unknown keys
- reject type-mismatched values
- only persist validated keys
- reply with the applied values

This milestone explicitly does not implement immediate-collect, immediate-report, mode-switch, or low-power control commands.

## Error Handling

- `main.lua` should fail fast only on unrecoverable startup problems such as a broken config layer
- collection errors stay local to the failed module and are represented in the snapshot
- MQTT publication failure should be logged but must not stop the periodic collection loop
- config update validation errors should be reported in the cloud reply path and must not corrupt persisted config

## Testing

The new structure requires application-layer tests in addition to existing driver tests.

### Required Updates

- update `tests/main_test.lua` to match the formal application entrypoint
- stop asserting the old per-sensor demo loop layout

### New Tests

- `tests/app_config_test.lua`
  - default config load
  - persisted config load
  - whitelist validation
  - config update persistence

- `tests/app_state_test.lua`
  - in-memory latest snapshot update
  - persisted latest snapshot load/save

- `tests/app_collect_test.lua`
  - successful snapshot assembly
  - partial failure handling
  - `glbs` integration and door-state integration

- `tests/gmqtt_test.lua`
  - real snapshot publication path
  - `dp/get` through config/state
  - `dp/set` validation and persistence calls

Existing driver tests for `gadc`, `gsht30`, `gbaro`, and `glbs` remain in place.

## Success Criteria

This milestone is complete when:

- `main.lua` starts the formal application entrypoint
- runtime config persists through `fskv`
- latest snapshot persists through `fskv`
- one periodic task collects real data from the existing modules
- MQTT publication uses real collected values instead of random data
- cloud config writes update validated persisted config
- the Lua test suite is updated to reflect the new entrypoint and new app modules
