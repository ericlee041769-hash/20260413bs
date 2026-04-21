# SMS Alarm Design

## Goal

Add application-layer SMS alarm delivery on top of the existing collection loop with these constraints:

- send SMS only, no SMS receive handling
- no retry or follow-up logic when sending fails
- send only when an alarm changes from normal to active
- if multiple alarms become active in the same cycle, merge them into one SMS
- keep `config.lua` as the only configuration definition entrypoint

This design intentionally limits scope to periodic collection alarms. It does not include event-driven door interrupt processing, low-power mode orchestration, or cross-reboot alarm deduplication.

## Context

The current repository already has:

- `application.lua` coordinating config load, module init, collection, state save, and MQTT report
- `app_collect.lua` building a normalized snapshot from battery, current, door, LBS, temperature, and pressure modules
- `app_state.lua` persisting the latest snapshot with `fskv`
- `app_config.lua` persisting runtime config with `fskv`
- `gmqtt.lua` exposing `dp/get` and `dp/set`

The first application milestone explicitly excluded SMS and the alarm engine. The hardware plan now requires warning output through SMS when collection data exceeds configured thresholds:

- temperature high or low
- temperature delta above 5 degrees
- current high or low
- pressure delta outside `1.0 ~ 1.5`
- door open duration above configured timeout

The user clarified the required behavior:

- send once on the transition from normal to abnormal
- support exactly one alarm phone number
- merge same-cycle alarms into one message
- all configurable and mutable parameters must be defined from `config.lua`

## Scope

### Included

- SMS sending wrapper for alarm notifications
- application-layer alarm evaluation on each collection cycle
- merged SMS text for same-cycle new alarms
- in-memory alarm runtime state for edge-trigger behavior
- new runtime config items for alarm phone number and temperature delta threshold
- `dp/get` and `dp/set` support for the new runtime config fields
- tests for alarm evaluation, SMS wrapper integration, and config updates

### Excluded

- SMS receive support
- SMS retry or resend queues
- handling `SMS_INC` or `SMS_SENT`
- event-driven door wakeup flow
- low-power sleep and wake scheduling
- cross-reboot persistence of alarm active state
- sensor filtering algorithms from the hardware plan
- MQTT alarm-specific publish channel

## Configuration Model

`config.lua` becomes the only configuration definition entrypoint. All configurable values, type metadata, and mutability metadata are defined there. `PROJECT` and `VERSION` remain fixed boot constants in `main.lua` and are not part of the mutable configuration model.

### Required Configuration Layout

`config.lua` should define:

- static transport credentials such as `MQTT`
- runtime default values
- runtime field type definitions
- runtime mutable-field definitions

Recommended structure:

```lua
local config = {}

config.MQTT = {
    -- existing MQTT config
}

config.RUNTIME_DEFAULTS = {
    sample_interval_ms = 10000,
    report_interval_ms = 10000,
    airlbs_project_id = "",
    airlbs_project_key = "",
    airlbs_timeout = 10000,
    temp_low = -40,
    temp_high = 85,
    temp_diff_high = 5,
    current_low = 0,
    current_high = 50000,
    pressure_diff_low = 1.0,
    pressure_diff_high = 1.5,
    door_open_warn_ms = 5000,
    alarm_sms_phone = "15025376653"
}

config.RUNTIME_FIELD_TYPES = {
    sample_interval_ms = "number",
    report_interval_ms = "number",
    airlbs_project_id = "string",
    airlbs_project_key = "string",
    airlbs_timeout = "number",
    temp_low = "number",
    temp_high = "number",
    temp_diff_high = "number",
    current_low = "number",
    current_high = "number",
    pressure_diff_low = "number",
    pressure_diff_high = "number",
    door_open_warn_ms = "number",
    alarm_sms_phone = "string"
}

config.RUNTIME_MUTABLE_FIELDS = {
    sample_interval_ms = true,
    report_interval_ms = true,
    airlbs_project_id = true,
    airlbs_project_key = true,
    airlbs_timeout = true,
    temp_low = true,
    temp_high = true,
    temp_diff_high = true,
    current_low = true,
    current_high = true,
    pressure_diff_low = true,
    pressure_diff_high = true,
    door_open_warn_ms = true,
    alarm_sms_phone = true
}

return config
```

### `app_config.lua` Responsibility

`app_config.lua` no longer owns default values or field definitions. It becomes the runtime config storage and validation layer:

- load defaults from `config.RUNTIME_DEFAULTS`
- overlay persisted values from `fskv`
- validate updates with `config.RUNTIME_FIELD_TYPES`
- allow updates only for `config.RUNTIME_MUTABLE_FIELDS`
- persist valid results back to `fskv`

The existing public API remains unchanged:

- `app_config.load()`
- `app_config.get()`
- `app_config.update(changes)`

This keeps the rest of the app stable while enforcing the user requirement that `config.lua` is the only parameter definition entrypoint.

## Architecture

Add two focused modules above the existing collection layer:

- `app_alarm.lua`
  - pure application alarm evaluation
  - compares the current snapshot against runtime thresholds
  - maintains edge-trigger alarm state in memory
  - builds merged SMS text for same-cycle new alarms

- `app_sms.lua`
  - SMS send wrapper only
  - exposes one send helper for alarm text
  - does not register any receive or result callbacks

`application.lua` remains the coordinator. It wires collection, latest-state persistence, alarm evaluation, SMS send, and telemetry publish without mixing the alarm rules into sensor or transport modules.

### File Responsibilities

- `config.lua`
  - only parameter definition entrypoint
  - static config plus runtime config metadata

- `app_config.lua`
  - runtime config load/get/update backed by `fskv`

- `app_alarm.lua`
  - alarm rule evaluation
  - edge-trigger state updates
  - merged SMS message construction

- `app_sms.lua`
  - SMS send wrapper around LuatOS SMS API

- `application.lua`
  - owns in-memory alarm runtime state
  - calls `app_alarm.evaluate(...)`
  - calls `app_sms.send_alert(...)` when needed

- `gmqtt.lua`
  - continues to route `dp/get` and `dp/set`
  - reflects new runtime config fields through `app_config`

## Alarm Evaluation Model

`app_alarm.lua` provides a single business entrypoint:

```lua
local result = app_alarm.evaluate(cfg, snapshot, runtime, now_ms)
```

Inputs:

- `cfg`: current runtime config
- `snapshot`: one collection result from `app_collect.collect_once()`
- `runtime`: in-memory alarm state from the previous cycle
- `now_ms`: current timestamp in milliseconds

Returned result:

- `active_map`: current active alarm keys
- `new_alarm_keys`: alarms that became active in this cycle
- `should_send_sms`: whether a merged SMS should be sent now
- `sms_text`: merged SMS text when `should_send_sms` is true
- `runtime`: next in-memory alarm state for the next cycle

### Alarm Keys

Each alarm uses a stable key:

- `door_open_timeout`
- `temp1_low`
- `temp1_high`
- `temp2_low`
- `temp2_high`
- `temp_diff_high`
- `current_low`
- `current_high`
- `pressure_diff_low`
- `pressure_diff_high`

### Rule Set

#### Temperature High and Low

Evaluate each SHT30 channel independently:

- only evaluate channels with `ok == true`
- trigger low alarm when temperature is below `cfg.temp_low`
- trigger high alarm when temperature is above `cfg.temp_high`

#### Temperature Delta

Only evaluate when both temperature channels are valid:

- `delta_t = math.abs(t1 - t2)`
- trigger `temp_diff_high` when `delta_t > cfg.temp_diff_high`

#### Current High and Low

Use the current project data shape as-is:

- compare `snapshot.current_sensor_mv` against `cfg.current_low` and `cfg.current_high`
- no ampere conversion or calibration work is included in this scope

#### Pressure Delta

Only evaluate when both pressure channels are valid:

- `delta_p = math.abs(p2 - p1)`
- trigger `pressure_diff_low` when `delta_p < cfg.pressure_diff_low`
- trigger `pressure_diff_high` when `delta_p > cfg.pressure_diff_high`

#### Door Open Timeout

Use a timer carried in `runtime`:

- when `snapshot.door_open == true` and no open timestamp exists, set `door_open_since_ms = now_ms`
- while the door remains open, trigger `door_open_timeout` when `now_ms - door_open_since_ms >= cfg.door_open_warn_ms`
- when the door closes, clear the open timestamp and clear the active door alarm

### Edge Trigger Policy

The alarm engine only sends SMS for new activations:

- active now and inactive before: new alarm, eligible for SMS
- active now and active before: no repeated SMS
- inactive now and active before: clear the active state
- inactive now and inactive before: no action

If the device reboots while the physical alarm condition still exists, the first post-reboot evaluation is treated as a new activation and may send one SMS again. This is intentional for this milestone because alarm active state is not persisted.

### Sensor Failure Policy

Sensor read failures do not create SMS alarms in this scope:

- invalid temperature channels are skipped
- invalid pressure channels are skipped
- invalid current value is skipped
- collection still produces a snapshot and the app continues running

This keeps the scope focused on threshold alarms rather than transport or device-health alarms.

## SMS Delivery

`app_sms.lua` exposes:

```lua
local ok = app_sms.send_alert(phone, text)
```

Implementation rules:

- use `sms.sendLong(phone, text, true).wait()`
- do not use `sms.send(...)`
- do not subscribe to `SMS_SENT`
- do not register `SMS_INC`
- return `true` or `false`
- log failures only

`sendLong(...).wait()` is preferred because same-cycle merged alarms may exceed the single-SMS byte limit and the current collection loop already runs inside a task context.

### Failure Handling

If SMS send fails:

- log the failure
- do not retry
- do not enqueue for later resend
- do not block future collection cycles

The alarm active state still advances normally. This matches the user requirement that failed sends need no further handling.

## SMS Text Format

One SMS is generated per cycle when there is at least one new alarm. The text is concise, stable, and value-oriented.

Recommended format:

```text
告警:门持续打开超时; 温度1高温=86.2; 温差异常=6.1; 电流高=53000; 压差异常=0.7; 时间=2026-04-21 14:32:10
```

Formatting rules:

- prefix with `告警:`
- merge all new alarms from the same cycle into one message
- join segments with `; `
- include key measured values
- append snapshot timestamp at the end
- keep segment order stable

Suggested segment order:

1. `door_open_timeout`
2. `temp1_low`
3. `temp1_high`
4. `temp2_low`
5. `temp2_high`
6. `temp_diff_high`
7. `current_low`
8. `current_high`
9. `pressure_diff_low`
10. `pressure_diff_high`

## Application Flow Changes

The existing collection task in `application.lua` changes from:

1. load config
2. collect snapshot
3. save latest snapshot
4. publish snapshot when report interval is due
5. wait for next cycle

To:

1. load config
2. collect snapshot
3. save latest snapshot
4. evaluate alarms with `app_alarm.evaluate(...)`
5. replace in-memory `alarm_runtime`
6. if `should_send_sms == true`, call `app_sms.send_alert(cfg.alarm_sms_phone, sms_text)`
7. publish snapshot when report interval is due
8. wait for next cycle

### Runtime State Placement

Alarm runtime state lives only in the application task memory, for example:

```lua
local alarm_runtime = {
    active_map = {},
    door_open_since_ms = nil
}
```

This state is not persisted with `fskv`.

## MQTT Integration

No new MQTT command model is introduced. The existing config flow remains:

- `dp/get` returns current runtime config values and latest snapshot
- `dp/set` applies validated runtime config changes through `app_config.update(...)`

Because `config.lua` defines runtime defaults and mutable fields, the new config items must appear through the same path:

- `temp_diff_high`
- `alarm_sms_phone`

Other existing threshold fields continue to work through the same update path.

## Error Handling

- module init failure remains a startup failure handled by `application.start()`
- collection errors remain localized in the snapshot
- alarm evaluation must tolerate missing or partial snapshot values
- SMS send failure is logged and ignored
- MQTT publish failure remains logged and non-fatal
- invalid `dp/set` changes must not corrupt persisted config

This preserves the current degraded-but-running behavior.

## Testing

### Update Existing Tests

- `tests/app_config_test.lua`
  - verify defaults come from `config.lua`
  - verify persisted overrides still work
  - verify `temp_diff_high` and `alarm_sms_phone` are accepted
  - verify only mutable fields can be updated

- `tests/gmqtt_test.lua`
  - verify `dp/get` includes the new runtime config fields
  - verify `dp/set` can update the new fields through `app_config`

### New Tests

- `tests/app_alarm_test.lua`
  - temperature high and low alarms
  - temperature delta alarm
  - current high and low alarms
  - pressure delta low and high alarms
  - door open timeout alarm
  - repeated active alarm does not resend SMS
  - alarm clears after recovery and can trigger again later
  - multiple new alarms in one cycle merge into one SMS

- `tests/app_sms_test.lua`
  - successful `sms.sendLong(...).wait()` path
  - failed send path returns false
  - no receive callback registration is used

- `tests/application_test.lua` or equivalent update
  - verify SMS send is invoked when a new alarm appears
  - verify SMS send is not invoked for already-active alarms
  - verify SMS failure does not stop the main loop behavior

## Success Criteria

This milestone is complete when:

- `config.lua` is the only configuration definition entrypoint
- runtime config still persists through `fskv`
- alarm evaluation runs on every collection cycle
- each alarm only sends SMS on normal-to-abnormal transition
- multiple new alarms in one cycle become one SMS
- SMS send uses LuatOS send-only behavior with no receive handling and no retry
- the new config items are readable and writable through the existing config pipeline
- tests cover the new config, alarm, SMS, and application integration behavior

## Deferred Work

The following items stay out of this implementation:

- door interrupt immediate-processing flow
- median or moving-average filtering for sensor values
- USB versus battery mode switching
- sleep, wakeup, and pre-wakeup orchestration
- persistent alarm deduplication across reboot
- dedicated MQTT alarm event publishing
