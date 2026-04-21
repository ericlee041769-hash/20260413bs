# DP Gateway Model Design

## Goal

Adapt the device MQTT payloads to the third-party gateway DP model so that:

- `dp/post` uses the gateway field names and direct-device payload shape
- `dp/get` returns the same gateway field names
- `dp/set` only accepts `phonenum`
- internal collection and config structures remain unchanged

## External DP Model

The gateway-facing fields are:

- `temp`
- `door`
- `humidity`
- `err`
- `time`
- `phonenum`
- `temp2`
- `humidity2`
- `tempdiff`
- `lpoint`

Field semantics:

- `temp` = `snapshot.temp_hum[0].temperature`
- `humidity` = `snapshot.temp_hum[0].humidity`
- `temp2` = `snapshot.temp_hum[1].temperature`
- `humidity2` = `snapshot.temp_hum[1].humidity`
- `door` = `snapshot.door_open`
- `err` = whether any alarm is currently active
- `time` = `snapshot.timestamp`
- `phonenum` = runtime config `alarm_sms_phone`
- `tempdiff` = `abs(temp2 - temp1)` when both temperatures are valid
- `lpoint` = `"lat,lng"` string

## MQTT Message Rules

### `dp/post`

Use the direct-device shape required by the gateway:

```json
{
  "dp": {
    "temp": 25.2,
    "door": false
  }
}
```

Do not include `deviceId` in the posted body.

### `dp/get`

Return only the gateway field names requested by the platform. Do not expose internal keys like `latest`, `alarm_sms_phone`, `temp_hum`, or `location`.

### `dp/set`

Accept only:

- `phonenum`

Map it to internal runtime config:

- `phonenum` -> `alarm_sms_phone`

Ignore all other fields, even if the external platform marks them as read/write.

Successful `dp/set/reply` should echo only accepted external keys:

```json
{
  "timestamp": 1601196762389,
  "messageId": "same-as-request",
  "dp": {
    "phonenum": "13800138000"
  },
  "success": true
}
```

## Internal Boundary

Keep the existing internal structures:

- `app_collect.lua` keeps returning the current normalized snapshot
- `app_config.lua` keeps storing `alarm_sms_phone`
- `app_alarm.lua` keeps evaluating alarms on the normalized snapshot

The gateway adaptation happens only at the MQTT boundary, primarily in `gmqtt.lua` and the MQTT payload builder.

## Testing

Add or update tests so that:

- `dp/post` sends the gateway-facing field set
- `dp/post` body omits `deviceId`
- `dp/get` returns gateway-facing fields only
- `dp/set` accepts only `phonenum`
- `dp/set` ignores writes to runtime telemetry fields
