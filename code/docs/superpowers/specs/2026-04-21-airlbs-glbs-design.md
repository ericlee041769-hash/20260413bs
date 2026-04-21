# AirLBS glbs Design

## Goal

Add a Lua module that wraps LuatOS `airlbs.request()` behind a small stateful API, exposes explicit initialization and coordinate retrieval functions, and enforces a 60-second minimum request interval with cached fallback coordinates.

## Context

The current codebase follows a one-module-per-capability style such as `gadc.lua`, `gsht30.lua`, and `gbaro.lua`. The new AirLBS wrapper should match that pattern:

- one dedicated module file
- explicit `init(...)` function
- explicit data retrieval function
- simple return shape for callers

The user-provided AirLBS API contract is:

- positioning uses `airlbs.request(param)`
- required request input is `project_id`
- optional inputs are `project_key`, `timeout`, `adapter`, and `wifi_info`
- success returns `true, { lat = ..., lng = ... }`
- failure returns `false, nil`

The user-approved wrapper behavior is:

- create a dedicated module named `glbs.lua`
- expose `init(cfg)` and `get_location()`
- return coordinates as an array table in `{lat, lng}` order
- when less than 60 seconds have passed since the last real request, return the last successful coordinates
- when no successful coordinates have ever been obtained, return `{0, 0}`
- when a fresh request is due but fails, fall back to the last successful coordinates; if none exist, return `{0, 0}`

## Module Design

Create `glbs.lua` as a stateful wrapper around the platform `airlbs` library.

### Public API

- `glbs.init(cfg)`
- `glbs.get_location()`

### Initialization Contract

`glbs.init(cfg)` accepts a table with these fields:

- `project_id` required string
- `project_key` optional string
- `timeout` optional number, default `10000`
- `adapter` optional number or `nil`
- `wifi_info` optional table or `nil`

`glbs.init(cfg)` validates the required configuration, stores a normalized copy inside the module, clears previous runtime state, and returns `true` on success. Invalid configuration returns `false` and logs an error.

State reset on init:

- clear last successful coordinates
- clear last request timestamp
- clear stored config before replacing it

## Coordinate Retrieval Behavior

`glbs.get_location()` always returns a table in `{lat, lng}` order.

### First Call

If the module has been initialized and no previous request has been sent, `glbs.get_location()` immediately performs one `airlbs.request(...)` call.

- on success: cache and return `{lat, lng}`
- on failure: return `{0, 0}`

### Calls Inside 60 Seconds

If fewer than 60 seconds have elapsed since the last real AirLBS request, `glbs.get_location()` does not call `airlbs.request(...)`.

- if cached coordinates exist: return the cached `{lat, lng}`
- otherwise: return `{0, 0}`

### Calls After 60 Seconds

If at least 60 seconds have elapsed since the last real AirLBS request, `glbs.get_location()` performs a new request.

- on success: update the cache and return the fresh `{lat, lng}`
- on failure with cache present: return the cached `{lat, lng}`
- on failure without cache: return `{0, 0}`

## Time Base

The 60-second gate is measured from the timestamp of the last actual call to `airlbs.request(...)`, not from the last call to `glbs.get_location()`.

This avoids a stale-cache situation where frequent reads would indefinitely postpone the next real location refresh.

The implementation should use a simple millisecond clock helper based on `os.time()` because the existing project already uses that pattern in `iot.lua`.

## Internal State

The module maintains:

- normalized request config
- last successful coordinates
- last request timestamp in milliseconds
- initialization state flag

Suggested cache shape:

```lua
local last_location = { 0, 0 }
local has_last_location = false
```

This keeps the public return contract simple while distinguishing between a real successful `{0, 0}` result and the fallback default.

## Error Handling

The wrapper should stay simple for callers:

- `glbs.init(cfg)` returns `true` or `false`
- `glbs.get_location()` always returns a coordinate table

Logging expectations:

- log configuration errors during `init`
- log missing initialization if `get_location()` is called before `init`
- log failed AirLBS requests when a fresh request was attempted

`glbs.get_location()` must not throw on ordinary request failures. The fallback table is the caller-visible error model.

## Testing

Add `tests/glbs_test.lua` using fake globals in the same style as the existing Lua tests.

Tests should cover:

- `init` rejects missing `project_id`
- `init` accepts valid config and resets runtime state
- first `get_location()` triggers one AirLBS request and returns `{lat, lng}` on success
- repeated call inside 60 seconds returns cached coordinates and does not trigger another request
- repeated call inside 60 seconds without any successful cache returns `{0, 0}`
- call after 60 seconds triggers a new request
- failed request after a previous success returns the cached coordinates
- failed request without any previous success returns `{0, 0}`
- calling `get_location()` before `init` returns `{0, 0}`

The tests should mock:

- `airlbs.request`
- `os.time`
- `log.error`

This allows deterministic verification of interval control and fallback behavior.

## Integration Scope

This work only adds the reusable wrapper module and its tests. It does not add a background polling task to `main.lua` unless a later requirement explicitly asks for application-level integration.
