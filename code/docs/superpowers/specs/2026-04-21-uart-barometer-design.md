# UART Barometer Design

## Goal

Add a Lua module that manages two UART-connected barometers on `UART1` and `UART2`, exposes a small synchronous API matching the existing sensor modules, and integrates a lightweight logging loop into `main.lua`.

## Context

The current codebase already uses one-module-per-device wrappers such as `gadc.lua` and `gsht30.lua`. The new UART barometer should follow the same style:

- module-level constants for managed buses
- `init()` to configure hardware
- `read(id)` to read one device
- `read_all()` to read all managed devices

The protocol details provided by the user are:

- UART settings: `9600 8N1`
- request frame: `0x55 + length + command + crc`
- response frame: `0xAA + length + type + payload + crc`
- CRC algorithm: `CRC-8/MAXIM`
- read pressure only after reading temperature for compensation
- temperature payload type: `0x0A`, `S16`, value = raw / 10
- real-time pressure payload type: `0x09`, `U32`, value = raw / 1000 kPa

## Module Design

Create `gbaro.lua` as a dedicated device wrapper.

### Public API

- `gbaro.UART1 = 1`
- `gbaro.UART2 = 2`
- `gbaro.BAUD_RATE = 9600`
- `gbaro.CMD_CAL_T = 0x0E`
- `gbaro.CMD_CAL_P1 = 0x0D`
- `gbaro.init()`
- `gbaro.read(id)`
- `gbaro.read_all()`

### Return Shape

`gbaro.read(id)` returns:

- success: `true, { temperature = 25.8, pressure = 100.0, temperature_raw = 258, pressure_raw = 100000 }`
- failure: `false, { error = "..." }`

`gbaro.read_all()` returns:

```lua
{
    [gbaro.UART1] = {
        ok = true,
        temperature = 25.8,
        pressure = 100.0,
        temperature_raw = 258,
        pressure_raw = 100000
    },
    [gbaro.UART2] = {
        ok = false,
        error = "crc mismatch"
    }
}
```

## Internal Flow

The implementation stays synchronous and uses `uart.write()` plus `uart.read()` instead of callback-driven receive handling. This keeps the API aligned with the rest of the repository and makes the module easy to unit test with a fake `uart` table.

Internal helpers:

- validate managed UART id
- build a request frame for a command
- compute CRC-8/MAXIM
- clear stale receive bytes before each command
- write the request frame
- poll `uart.read()` until a complete response frame is collected or timeout occurs
- validate header, length, type, and CRC
- decode signed 16-bit temperature and unsigned 32-bit pressure payloads

`gbaro.read(id)` performs:

1. read temperature using `CMD_CAL_T`
2. read real-time pressure using `CMD_CAL_P1`
3. merge both readings into one result

## Error Handling

`gbaro.read(id)` returns structured failures with one of these messages:

- `invalid uart id`
- `uart write failed`
- `uart response timeout`
- `invalid frame header`
- `invalid frame length`
- `crc mismatch`
- `unexpected frame type`
- `invalid temperature payload`
- `invalid pressure payload`

`gbaro.init()` returns `false` if either `uart.setup()` call fails and logs the failing UART id.

`gbaro.read_all()` never aborts the full read on a single-device failure. It returns one result table per managed UART id.

## Testing

Add `tests/gbaro_test.lua` using the same fake-bottom-layer pattern already used in `tests/gadc_test.lua` and `tests/gsht30_test.lua`.

Tests cover:

- constants and `init()` configuration
- request frame generation for temperature and pressure commands
- successful one-device read including temperature-before-pressure ordering
- `read_all()` reading both UART ids
- invalid uart id
- timeout
- bad header
- CRC mismatch
- unexpected frame type

Update `tests/main_test.lua` so the application requires `gbaro`, starts one extra task, initializes the barometer module, and logs readings from both UARTs.

## Main Integration

`main.lua` will:

- require `gbaro`
- create a third background task
- initialize the UART barometer module once inside that task
- log the state of `UART1` and `UART2` once per second

This keeps the integration consistent with the existing `gadc` and `gsht30` test loops.
