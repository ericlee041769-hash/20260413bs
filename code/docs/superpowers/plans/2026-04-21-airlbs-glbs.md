# AirLBS glbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `glbs.lua` wrapper for LuatOS `airlbs.request()` that initializes request config, returns `{lat, lng}` coordinates, caches the last successful result, and enforces a 60-second minimum refresh interval.

**Architecture:** Keep the feature isolated in a new `glbs.lua` module that owns config validation, request timing, cached coordinates, and fallback behavior. Cover the module with a dedicated script-style Lua test that fakes `airlbs`, `os.time`, and `log`, while leaving the rest of the application unchanged.

**Tech Stack:** Lua, LuatOS `airlbs` API, script-style Lua tests with fake globals, local Lua runtime at `D:\tool\lua\bin\lua.cmd`

---

### Task 1: Add the first failing tests for init validation and zero fallback

**Files:**
- Create: `tests/glbs_test.lua`

- [ ] **Step 1: Write the failing test scaffold**

```lua
local request_calls = {}
local request_results = {}
local error_logs = {}
local current_time = 100

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message .. ": expected true, got " .. tostring(value))
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message .. ": expected false, got " .. tostring(value))
	end
end

local function assert_location(actual, expected_lat, expected_lng, message)
	assert_equal(type(actual), "table", message .. " type")
	assert_equal(actual[1], expected_lat, message .. " lat")
	assert_equal(actual[2], expected_lng, message .. " lng")
end

_G.airlbs = {
	request = function(param)
		request_calls[#request_calls + 1] = param
		local next_result = request_results[1] or { false, nil }
		if #request_results > 0 then
			table.remove(request_results, 1)
		end
		return next_result[1], next_result[2]
	end
}

_G.log = {
	error = function(...)
		error_logs[#error_logs + 1] = { ... }
	end
}

_G.os = {
	time = function()
		return current_time
	end
}

local module_loader, load_err = loadfile("glbs.lua")
assert(module_loader, load_err)
local glbs = module_loader()

local before_init = glbs.get_location()
assert_location(before_init, 0, 0, "before init fallback")
assert_equal(#error_logs, 1, "before init should log once")

assert_false(glbs.init({}), "init should reject missing project_id")
assert_equal(#error_logs, 2, "missing project_id should log")

assert_true(glbs.init({ project_id = "demo_project" }), "init should accept valid project_id")

print("glbs_test.lua: PASS")
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\glbs_test.lua`  
Expected: FAIL because `glbs.lua` does not exist yet.

### Task 2: Implement the minimal module to satisfy the first tests

**Files:**
- Create: `glbs.lua`
- Test: `tests/glbs_test.lua`

- [ ] **Step 1: Write the minimal `glbs.lua` implementation**

```lua
local glbs = {}

local DEFAULT_TIMEOUT = 10000
local ZERO_LOCATION = { 0, 0 }

local is_inited = false
local request_cfg = nil
local last_request_ms = nil
local last_location = { 0, 0 }
local has_last_location = false

local function log_error(tag, ...)
	if log and log.error then
		log.error(tag, ...)
	end
end

local function copy_location(source)
	return { source[1], source[2] }
end

local function reset_runtime_state()
	last_request_ms = nil
	last_location = { 0, 0 }
	has_last_location = false
end

function glbs.init(cfg)
	if type(cfg) ~= "table" or type(cfg.project_id) ~= "string" or cfg.project_id == "" then
		log_error("glbs.init", "project_id is required")
		is_inited = false
		request_cfg = nil
		reset_runtime_state()
		return false
	end

	request_cfg = {
		project_id = cfg.project_id,
		project_key = cfg.project_key,
		timeout = cfg.timeout or DEFAULT_TIMEOUT,
		adapter = cfg.adapter,
		wifi_info = cfg.wifi_info
	}
	is_inited = true
	reset_runtime_state()
	return true
end

function glbs.get_location()
	if not is_inited then
		log_error("glbs.get_location", "module not initialized")
		return copy_location(ZERO_LOCATION)
	end

	if has_last_location then
		return copy_location(last_location)
	end

	return copy_location(ZERO_LOCATION)
end

return glbs
```

- [ ] **Step 2: Run the test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\glbs_test.lua`  
Expected: PASS

- [ ] **Step 3: Commit the minimal skeleton**

```bash
git add glbs.lua tests/glbs_test.lua
git commit -m "Add initial glbs module skeleton"
```

### Task 3: Add failing tests for request forwarding, caching, and fallback refresh

**Files:**
- Modify: `tests/glbs_test.lua`

- [ ] **Step 1: Extend the test with request and cache scenarios**

```lua
request_calls = {}
request_results = {
	{ true, { lat = 31.1354542, lng = 121.5423279 } },
	{ true, { lat = 30.1234567, lng = 120.7654321 } },
	{ false, nil }
}
error_logs = {}
current_time = 100

assert_true(
	glbs.init({
		project_id = "demo_project",
		project_key = "demo_key",
		timeout = 15000,
		adapter = 3,
		wifi_info = {
			{ bssid = "24:32:AE:04:E1:67", rssi = -86 }
		}
	}),
	"init with request config"
)

local first_location = glbs.get_location()
assert_location(first_location, 31.1354542, 121.5423279, "first successful request")
assert_equal(#request_calls, 1, "first call should request once")
assert_equal(request_calls[1].project_id, "demo_project", "project_id should be forwarded")
assert_equal(request_calls[1].project_key, "demo_key", "project_key should be forwarded")
assert_equal(request_calls[1].timeout, 15000, "timeout should be forwarded")
assert_equal(request_calls[1].adapter, 3, "adapter should be forwarded")
assert_equal(request_calls[1].wifi_info[1].bssid, "24:32:AE:04:E1:67", "wifi_info should be forwarded")

current_time = 130
local cached_location = glbs.get_location()
assert_location(cached_location, 31.1354542, 121.5423279, "second call should use cache inside 60 seconds")
assert_equal(#request_calls, 1, "cached call should not request again")

current_time = 161
local refreshed_location = glbs.get_location()
assert_location(refreshed_location, 30.1234567, 120.7654321, "refresh after 60 seconds")
assert_equal(#request_calls, 2, "refresh should request again")

current_time = 222
local failed_refresh_location = glbs.get_location()
assert_location(failed_refresh_location, 30.1234567, 120.7654321, "failed refresh should return last success")
assert_equal(#request_calls, 3, "failed refresh should still attempt request")

assert_true(glbs.init({ project_id = "fresh_project" }), "re-init should reset state")
current_time = 300
request_calls = {}
request_results = {
	{ false, nil }
}

local first_failure_location = glbs.get_location()
assert_location(first_failure_location, 0, 0, "first failure without cache should return zero")
assert_equal(#request_calls, 1, "first failure should still attempt request")
assert_equal(request_calls[1].timeout, 10000, "default timeout should be 10000")
```

- [ ] **Step 2: Run the test and verify it fails for the expected reason**

Run: `D:\tool\lua\bin\lua.cmd tests\glbs_test.lua`  
Expected: FAIL because `glbs.get_location()` does not yet call `airlbs.request()` or enforce the 60-second cache rules.

### Task 4: Implement request timing, cache refresh, and fallback behavior

**Files:**
- Modify: `glbs.lua`
- Test: `tests/glbs_test.lua`

- [ ] **Step 1: Add clock, request, and cache helpers to `glbs.lua`**

```lua
local REQUEST_INTERVAL_MS = 60000

local function now_ms()
	return (os.time() or 0) * 1000
end

local function build_request_param()
	return {
		project_id = request_cfg.project_id,
		project_key = request_cfg.project_key,
		timeout = request_cfg.timeout,
		adapter = request_cfg.adapter,
		wifi_info = request_cfg.wifi_info
	}
end

local function request_due(current_ms)
	return last_request_ms == nil or (current_ms - last_request_ms) >= REQUEST_INTERVAL_MS
end

local function request_location(request_time_ms)
	local ok
	local data

	if not airlbs or type(airlbs.request) ~= "function" then
		log_error("glbs.get_location", "airlbs.request unavailable")
		last_request_ms = request_time_ms
		return false
	end

	last_request_ms = request_time_ms
	ok, data = airlbs.request(build_request_param())
	if ok and type(data) == "table" and type(data.lat) == "number" and type(data.lng) == "number" then
		last_location = { data.lat, data.lng }
		has_last_location = true
		return true
	end

	log_error("glbs.get_location", "airlbs request failed")
	return false
end
```

- [ ] **Step 2: Replace `glbs.get_location()` with the full cache-aware version**

```lua
function glbs.get_location()
	local current_ms

	if not is_inited then
		log_error("glbs.get_location", "module not initialized")
		return copy_location(ZERO_LOCATION)
	end

	current_ms = now_ms()
	if not request_due(current_ms) then
		if has_last_location then
			return copy_location(last_location)
		end
		return copy_location(ZERO_LOCATION)
	end

	if request_location(current_ms) then
		return copy_location(last_location)
	end

	if has_last_location then
		return copy_location(last_location)
	end

	return copy_location(ZERO_LOCATION)
end
```

- [ ] **Step 3: Run the test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\glbs_test.lua`  
Expected: PASS

- [ ] **Step 4: Commit the finished module behavior**

```bash
git add glbs.lua tests/glbs_test.lua
git commit -m "Implement cached AirLBS location wrapper"
```

### Task 5: Run regression verification for the Lua test scripts

**Files:**
- Test: `tests/io_test.lua`
- Test: `tests/gadc_test.lua`
- Test: `tests/gsht30_test.lua`
- Test: `tests/gbaro_test.lua`
- Test: `tests/main_test.lua`
- Test: `tests/glbs_test.lua`

- [ ] **Step 1: Run the full Lua test set**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\gadc_test.lua
D:\tool\lua\bin\lua.cmd tests\gsht30_test.lua
D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua
D:\tool\lua\bin\lua.cmd tests\main_test.lua
D:\tool\lua\bin\lua.cmd tests\glbs_test.lua
```

Expected: every script prints `PASS` and exits with code `0`.

- [ ] **Step 2: Review the final diff**

Run: `git diff -- glbs.lua tests/glbs_test.lua docs/superpowers/specs/2026-04-21-airlbs-glbs-design.md docs/superpowers/plans/2026-04-21-airlbs-glbs.md`  
Expected: only the new module, the new test, and the AirLBS docs change.
