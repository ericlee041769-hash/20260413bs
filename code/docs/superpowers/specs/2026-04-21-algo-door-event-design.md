# Algorithm And Door Event Design

## Goal

Implement three runtime behavior upgrades on top of the current application flow:

- sensor values exposed to alarms, persistence, and MQTT must become filtered formal values rather than raw reads
- door handling must become event-driven, with debounce and delayed timeout confirmation
- a door-open timeout must trigger SMS and MQTT immediately instead of waiting for the next periodic report slot

This design intentionally excludes low-power mode, VBUS power-mode switching, and cloud-triggered immediate collect/report commands.

## Scope

### Included

- add an application-layer algorithm module for filtered formal values
- maintain runtime history windows for temperature, humidity, and current
- reuse filtered values for alarm evaluation, latest-state persistence, and MQTT upload
- add door-edge event publication from the GPIO layer
- add `200ms` debounce handling in the application layer
- add delayed timeout confirmation for door-open alarm and immediate SMS/upload on first trigger

### Excluded

- USB vs battery mode switching
- PM sleep / wake scheduling
- BQ25616 `CE` / `PG` / `STAT` integration
- cloud-triggered immediate collect/report commands
- pressure filtering or scoring system

## Architecture

Keep raw device access modules unchanged and insert a narrow business layer between raw collection and alarm/upload handling.

### New Module

- `app_algorithm.lua`
  - owns runtime history state for the filter windows
  - accepts one raw snapshot plus previous runtime state
  - returns a processed snapshot plus next runtime state

### Existing Module Changes

- `application.lua`
  - creates and retains `algo_runtime`
  - applies `app_algorithm` to each collected snapshot before alarm evaluation
  - subscribes to door-edge events
  - runs debounce and delayed timeout confirmation tasks
  - triggers immediate process-and-report flow when door timeout is first confirmed

- `ggpio.lua`
  - changes door interrupt mode to falling-edge-first behavior
  - publishes a system event for door edges rather than only logging
  - still exposes `get_door_state()` for post-debounce confirmation

- `gmqtt.lua`
  - unchanged contract, but now receives already-filtered formal snapshot values

- `app_alarm.lua`
  - unchanged rule set
  - continues to determine whether the door timeout is a new alarm

## Filter Model

Filtered values become the formal device values. Raw values stay internal to the runtime state only.

### Temperature And Humidity

For each SHT30 channel independently:

1. keep the most recent three raw values for temperature
2. keep the most recent three raw values for humidity
3. compute the median of the current window
4. apply EMA on top of the median

Recommended EMA:

```lua
filtered = alpha * median + (1 - alpha) * last_filtered
```

Where:

- first valid sample for a channel initializes `last_filtered`
- `alpha` is fixed in code for this milestone

Both filtered temperature and filtered humidity overwrite:

- `snapshot.temp_hum[id].temperature`
- `snapshot.temp_hum[id].humidity`

### Current

For current:

1. keep the most recent three raw `current_sensor_mv` samples
2. compute a three-point arithmetic mean
3. overwrite `snapshot.current_sensor_mv` with the averaged value

`current_raw` and `current_mv` remain raw hardware-read fields because they are transport/debug fields rather than business-threshold inputs.

## Algorithm Runtime State

`app_algorithm.lua` maintains runtime-only state shaped like:

```lua
{
  temp_hum = {
    [0] = {
      temp_window = { 25.1, 25.4, 25.2 },
      hum_window = { 50.0, 50.8, 50.2 },
      filtered_temp = 25.2,
      filtered_hum = 50.3
    },
    [1] = { ... }
  },
  current = {
    window = { 980, 1000, 1020 }
  }
}
```

This runtime state is not persisted to `fskv`. After reboot, filtering restarts from empty history.

## Door Event Flow

The hardware plan requires falling-edge wake semantics plus debounce and delayed timeout confirmation.

### GPIO Layer

- configure the door interrupt as falling edge when available
- publish one system event, for example `APP_DOOR_EDGE`, with the pin and level
- keep logging the edge for serial diagnostics

### Application Layer

On each door-edge event:

1. wait `200ms`
2. re-read door state through `ggpio.get_door_state()`
3. if the door is not open anymore, treat it as bounce and stop
4. if the door is open, schedule or keep one pending timeout confirmation task
5. after `cfg.door_open_warn_ms`, re-read the door state again
6. if still open, run one immediate business cycle:
   - collect raw snapshot
   - apply algorithm filtering
   - evaluate alarms
   - persist latest snapshot
   - send SMS when `app_alarm` says this is a new alarm
   - force immediate MQTT upload regardless of normal report interval

### Deduplication

The immediate timeout path reuses `app_alarm.evaluate(...)`.

This means:

- the first transition into `door_open_timeout` sends SMS and uploads immediately
- the normal periodic loop does not resend while the alarm remains active
- closing the door clears runtime door state, allowing the next long-open event to trigger again

## Error Handling

- invalid or failed sensor reads keep their current degraded behavior
- algorithm filtering skips invalid channels and keeps prior runtime history unchanged for those channels
- duplicate door-edge events must not create multiple concurrent timeout tasks
- debounce or timeout tasks must re-check live door state before acting

## Testing

Add tests for:

- `app_algorithm.lua` median + EMA behavior on both SHT30 channels
- `app_algorithm.lua` three-point current averaging
- runtime history carry-over across cycles
- `ggpio.lua` falling-edge event publication
- `application.lua` debounce handling and timeout-triggered immediate flow
- no duplicate SMS for a persistent open-door alarm
