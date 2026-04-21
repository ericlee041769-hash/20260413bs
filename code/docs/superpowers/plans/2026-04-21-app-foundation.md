# Application Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current sensor-demo entrypoint with a formal application loop that persists runtime config and latest telemetry with `fskv`, aggregates the existing sensor modules into one snapshot, and publishes real data through MQTT.

**Architecture:** Keep the existing sensor and transport modules, then add a thin application layer composed of `app_config.lua`, `app_state.lua`, and `app_collect.lua`. Update `gmqtt.lua`, `application.lua`, `main.lua`, and the Lua tests so the repository moves from isolated module demos to one cohesive business entrypoint without implementing alarms or low-power control yet.

**Tech Stack:** Lua, LuatOS `fskv`, existing `gadc` / `gsht30` / `gbaro` / `glbs` modules, script-style Lua tests with fake globals, local Lua runtime at `D:\tool\lua\bin\lua.cmd`

---

### Task 1: Realign the test baseline around the formal application entrypoint

**Files:**
- Modify: `tests/main_test.lua`

- [ ] **Step 1: Write the failing `main.lua` integration expectations**

```lua
local app_start_calls = 0

local fake_application = {
	start = function()
		app_start_calls = app_start_calls + 1
		return true
	end
}

fake_modules.application = fake_application

assert(required_modules.application, "main.lua should require application")
assert(app_start_calls == 1, "main.lua should start application once")
assert(#task_queue == 0, "main.lua should not register sensor demo loops directly")
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\main_test.lua`  
Expected: FAIL because `main.lua` still owns the old sensor-loop logic instead of delegating to `application.start()`.

### Task 2: Add config persistence and latest-state persistence modules

**Files:**
- Create: `app_config.lua`
- Create: `app_state.lua`
- Create: `tests/app_config_test.lua`
- Create: `tests/app_state_test.lua`

- [ ] **Step 1: Write the failing config and state tests**

```lua
local fake_store = {}
_G.fskv = {
	get = function(key) return fake_store[key] end,
	set = function(key, value) fake_store[key] = value return true end
}

local config_loader = loadfile("app_config.lua")
local app_config = config_loader()

local cfg = app_config.load()
assert(cfg.sample_interval_ms == 10000, "default sample interval")
assert(app_config.update({ report_interval_ms = 15000 }).report_interval_ms == 15000, "updated report interval")

local state_loader = loadfile("app_state.lua")
local app_state = state_loader()
local latest = app_state.save_latest({ timestamp = "2026-04-21 12:00:00" })
assert(latest.timestamp == "2026-04-21 12:00:00", "latest snapshot should be saved")
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
```

Expected: FAIL because the new modules do not exist yet.

- [ ] **Step 3: Implement minimal `app_config.lua`**

```lua
local app_config = {}

local CONFIG_KEY = "app:config"
local DEFAULT_CONFIG = {
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

- [ ] **Step 4: Implement minimal `app_state.lua`**

```lua
local app_state = {}

local LATEST_KEY = "app:latest"
local latest_snapshot = nil

function app_state.save_latest(snapshot)
	latest_snapshot = snapshot
	fskv.set(LATEST_KEY, snapshot)
	return latest_snapshot
end
```

- [ ] **Step 5: Run the tests and verify they pass**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
```

Expected: PASS

- [ ] **Step 6: Commit the persistence layer**

```bash
git add app_config.lua app_state.lua tests/app_config_test.lua tests/app_state_test.lua
git commit -m "Add persisted app config and state modules"
```

### Task 3: Add the unified collection module

**Files:**
- Create: `app_collect.lua`
- Create: `tests/app_collect_test.lua`

- [ ] **Step 1: Write the failing collection test**

```lua
_G.gadc = {
	read_battery = function() return 3800, 56 end,
	read_wcs1500_adc0 = function() return 1234, 500, 1000 end
}

_G.ggpio = {
	get_door_state = function() return false end
}

_G.gsht30 = {
	I2C0 = 0,
	I2C1 = 1,
	read_all = function()
		return {
			[0] = { ok = true, temperature = 25.2, humidity = 50.1 },
			[1] = { ok = true, temperature = 26.8, humidity = 60.3 }
		}
	end
}

local collect_loader = loadfile("app_collect.lua")
local app_collect = collect_loader()
local snapshot = app_collect.collect_once()
assert(snapshot.battery_mv == 3800, "battery should be included")
assert(snapshot.location[1] == 0, "default location should exist")
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua`  
Expected: FAIL because `app_collect.lua` does not exist yet.

- [ ] **Step 3: Implement `app_collect.lua`**

```lua
local app_collect = {}

function app_collect.collect_once()
	local battery_mv, battery_percent = gadc.read_battery()
	local current_raw, current_mv, current_sensor_mv = gadc.read_wcs1500_adc0()
	local location = glbs and glbs.get_location and glbs.get_location() or { 0, 0 }

	return {
		timestamp = os.date("%Y-%m-%d %H:%M:%S"),
		battery_mv = battery_mv,
		battery_percent = battery_percent,
		current_raw = current_raw,
		current_mv = current_mv,
		current_sensor_mv = current_sensor_mv,
		door_open = ggpio.get_door_state and ggpio.get_door_state() or false,
		location = location,
		temp_hum = gsht30.read_all(),
		pressure = gbaro.read_all()
	}
end
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua`  
Expected: PASS

- [ ] **Step 5: Commit the collection layer**

```bash
git add app_collect.lua tests/app_collect_test.lua
git commit -m "Add unified telemetry collection module"
```

### Task 4: Refactor `gmqtt.lua` to use real snapshot/config data

**Files:**
- Modify: `gmqtt.lua`
- Create: `tests/gmqtt_test.lua`

- [ ] **Step 1: Write the failing MQTT behavior test**

```lua
local published_snapshot = nil
local fake_app_config = {
	get = function()
		return { sample_interval_ms = 10000, report_interval_ms = 10000 }
	end,
	update = function(changes)
		return changes
	end
}

local fake_app_state = {
	get_latest = function()
		return { timestamp = "2026-04-21 12:00:00", battery_mv = 3800 }
	end
}

local ok = gmqtt.publish_snapshot({ timestamp = "2026-04-21 12:00:00", battery_mv = 3800 })
assert(ok == true, "gmqtt should publish provided snapshot")
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua`  
Expected: FAIL because `gmqtt.lua` still only exposes the random demo publication task.

- [ ] **Step 3: Implement snapshot publication and config-backed `dp/get` / `dp/set`**

```lua
function gmqtt.publish_snapshot(snapshot)
	if type(snapshot) ~= "table" then
		return false
	end

	return iot.publish_dp(snapshot)
end
```

```lua
local function handle_set(dp)
	local applied = app_config.update(dp)
	return applied
end
```

- [ ] **Step 4: Remove the random telemetry loop from `gmqtt.start()`**

```lua
function gmqtt.start(services)
	app_config = services.app_config
	app_state = services.app_state
	start_mqtt_connection_task()
	register_mqtt_receive_handler()
	register_mqtt_state_handlers()
	return true
end
```

- [ ] **Step 5: Run the test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua`  
Expected: PASS

- [ ] **Step 6: Commit the MQTT refactor**

```bash
git add gmqtt.lua tests/gmqtt_test.lua
git commit -m "Refactor MQTT flow to use app config and snapshots"
```

### Task 5: Replace the sensor-demo entrypoint with the formal application loop

**Files:**
- Modify: `application.lua`
- Modify: `main.lua`
- Modify: `tests/main_test.lua`

- [ ] **Step 1: Implement `application.start()` around the new app modules**

```lua
local app_config = require("app_config")
local app_state = require("app_state")
local app_collect = require("app_collect")
local gmqtt = require("gmqtt")

function application.start()
	local cfg = app_config.load()
	ggpio.init()
	gsht30.init()
	gbaro.init()
	glbs.init({
		project_id = cfg.airlbs_project_id,
		project_key = cfg.airlbs_project_key,
		timeout = cfg.airlbs_timeout
	})
	gmqtt.start({ app_config = app_config, app_state = app_state })
	sys.taskInit(function()
		while true do
			local snapshot = app_collect.collect_once()
			app_state.save_latest(snapshot)
			gmqtt.publish_snapshot(snapshot)
			sys.wait(cfg.sample_interval_ms)
		end
	end)
	return true
end
```

- [ ] **Step 2: Replace `main.lua` with the formal entrypoint**

```lua
PROJECT = "Air780EPM"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.config = require("config")
_G.application = require("application")

application.start()
sys.run()
```

- [ ] **Step 3: Update `tests/main_test.lua` to the new entrypoint contract**

```lua
assert(required_modules.application, "main.lua should require application")
assert(app_start_calls == 1, "main.lua should start application once")
assert(run_called, "main.lua should call sys.run")
assert(#task_queue == 0, "main.lua should not register direct sensor demo tasks")
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\main_test.lua
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua
D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua
```

Expected: PASS

- [ ] **Step 5: Commit the application entrypoint**

```bash
git add application.lua main.lua tests/main_test.lua
git commit -m "Replace sensor demo entrypoint with application loop"
```

### Task 6: Run full regression verification

**Files:**
- Test: `tests/io_test.lua`
- Test: `tests/gadc_test.lua`
- Test: `tests/gsht30_test.lua`
- Test: `tests/gbaro_test.lua`
- Test: `tests/glbs_test.lua`
- Test: `tests/app_config_test.lua`
- Test: `tests/app_state_test.lua`
- Test: `tests/app_collect_test.lua`
- Test: `tests/gmqtt_test.lua`
- Test: `tests/main_test.lua`

- [ ] **Step 1: Run the complete Lua regression set**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\gadc_test.lua
D:\tool\lua\bin\lua.cmd tests\gsht30_test.lua
D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua
D:\tool\lua\bin\lua.cmd tests\glbs_test.lua
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua
D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua
D:\tool\lua\bin\lua.cmd tests\main_test.lua
```

Expected: every script prints `PASS` and exits with code `0`.

- [ ] **Step 2: Review the diff boundary**

Run: `git diff -- app_config.lua app_state.lua app_collect.lua application.lua main.lua gmqtt.lua tests/main_test.lua tests/app_config_test.lua tests/app_state_test.lua tests/app_collect_test.lua tests/gmqtt_test.lua docs/superpowers/specs/2026-04-21-app-foundation-design.md docs/superpowers/plans/2026-04-21-app-foundation.md`  
Expected: only the application-foundation files for this milestone are changed.
