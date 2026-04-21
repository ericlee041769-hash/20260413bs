# Algorithm And Door Event Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add filtered formal values plus event-driven door timeout handling so alarms, latest persistence, SMS, and MQTT all use processed data and the door timeout can trigger immediate SMS/upload.

**Architecture:** Keep raw collection in `app_collect.lua`, add `app_algorithm.lua` for runtime filtering, and extend `application.lua` to run one shared process cycle for both periodic collection and door-timeout-triggered immediate handling. Publish door-edge events from `ggpio.lua`, then debounce and confirm the timeout in the application layer.

**Tech Stack:** Lua, LuatOS `sys` task/event APIs, existing `application.lua` / `app_collect.lua` / `app_alarm.lua` / `gmqtt.lua`, script-style Lua tests with fake globals, local Lua runtime at `D:\tool\lua\bin\lua.cmd`

---

### Task 1: Add failing tests for the algorithm layer

**Files:**
- Create: `tests/app_algorithm_test.lua`

- [ ] **Step 1: Write the failing filter tests**

```lua
local first_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 10, humidity = 50 },
		[1] = { ok = true, temperature = 20, humidity = 60 }
	},
	current_sensor_mv = 100
}

local second_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 30, humidity = 70 },
		[1] = { ok = true, temperature = 40, humidity = 80 }
	},
	current_sensor_mv = 200
}

local third_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 20, humidity = 60 },
		[1] = { ok = true, temperature = 30, humidity = 70 }
	},
	current_sensor_mv = 300
}

local _, runtime1 = app_algorithm.apply(first_snapshot, nil)
local _, runtime2 = app_algorithm.apply(second_snapshot, runtime1)
local output, runtime3 = app_algorithm.apply(third_snapshot, runtime2)

assert(output.temp_hum[0].temperature ~= 20, "formal temperature should be filtered")
assert(output.current_sensor_mv == 200, "current should use 3-point average")
assert(type(runtime3.temp_hum[0].filtered_temp) == "number", "runtime should retain filtered state")
```

- [ ] **Step 2: Run the algorithm test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\app_algorithm_test.lua`  
Expected: FAIL because `app_algorithm.lua` does not exist yet.

### Task 2: Implement the algorithm module and integrate it into the periodic flow

**Files:**
- Create: `app_algorithm.lua`
- Modify: `application.lua`
- Modify: `tests/application_test.lua`

- [ ] **Step 1: Implement the runtime filter module**

```lua
function app_algorithm.apply(snapshot, runtime)
	local next_snapshot = clone_snapshot(snapshot)
	local next_runtime = clone_runtime(runtime)
	-- update 3-point windows
	-- compute median
	-- compute EMA for temp/humidity
	-- compute 3-point mean for current
	return next_snapshot, next_runtime
end
```

- [ ] **Step 2: Route each periodic snapshot through the algorithm layer before alarms**

```lua
local processed_snapshot
processed_snapshot, algo_runtime = app_algorithm.apply(raw_snapshot, algo_runtime)
local alarm = app_alarm.evaluate(cfg, processed_snapshot, alarm_runtime, now_ms())
```

- [ ] **Step 3: Run the targeted tests and verify they pass**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\app_algorithm_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
```

Expected: PASS

### Task 3: Add failing tests for door-edge publication and event-driven timeout handling

**Files:**
- Modify: `tests/io_test.lua`
- Modify: `tests/application_test.lua`

- [ ] **Step 1: Add a GPIO event-publication assertion**

```lua
assert_equal(published[1].name, "APP_DOOR_EDGE", "door edge should publish system event")
assert_equal(published[1].args[2], 0, "door edge should carry falling level")
```

- [ ] **Step 2: Add an application timeout-trigger test**

```lua
assert_equal(send_alert_calls, 1, "door timeout should trigger immediate sms once")
assert_equal(publish_snapshot_calls, 1, "door timeout should trigger immediate upload once")
assert_equal(saved_latest_count, 1, "door timeout should persist the processed snapshot")
```

- [ ] **Step 3: Run the targeted tests and verify they fail**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
```

Expected: FAIL because door events are only logged and the application does not yet debounce or confirm timeout tasks.

### Task 4: Implement event-driven door debounce and immediate alarm/upload flow

**Files:**
- Modify: `ggpio.lua`
- Modify: `application.lua`

- [ ] **Step 1: Publish falling-edge door events from `ggpio.lua`**

```lua
local irq_mode = gpio.FALLING or gpio.BOTH
sys.publish("APP_DOOR_EDGE", pin, level)
```

- [ ] **Step 2: Add debounce and timeout-confirmation handling to `application.lua`**

```lua
sys.subscribe("APP_DOOR_EDGE", function(pin, level)
	sys.taskInit(function()
		sys.wait(200)
		if not ggpio.get_door_state() then
			return
		end
		-- wait cfg.door_open_warn_ms, re-check, then run immediate processing
	end)
end)
```

- [ ] **Step 3: Refactor one shared process helper for both periodic and immediate paths**

```lua
local function process_cycle(reason, force_report)
	-- collect raw snapshot
	-- apply algorithm
	-- evaluate alarm
	-- persist latest
	-- send sms if needed
	-- publish snapshot when forced or interval due
end
```

- [ ] **Step 4: Run targeted regression and verify it passes**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\app_algorithm_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
```

Expected: PASS

### Task 5: Run full regression

**Files:**
- Test: `tests\io_test.lua`
- Test: `tests\gadc_test.lua`
- Test: `tests\gsht30_test.lua`
- Test: `tests\gbaro_test.lua`
- Test: `tests\glbs_test.lua`
- Test: `tests\iot_test.lua`
- Test: `tests\app_config_test.lua`
- Test: `tests\app_state_test.lua`
- Test: `tests\app_collect_test.lua`
- Test: `tests\app_alarm_test.lua`
- Test: `tests\app_algorithm_test.lua`
- Test: `tests\app_sms_test.lua`
- Test: `tests\application_test.lua`
- Test: `tests\gmqtt_test.lua`
- Test: `tests\main_test.lua`

- [ ] **Step 1: Run the full Lua test set**

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\gadc_test.lua
D:\tool\lua\bin\lua.cmd tests\gsht30_test.lua
D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua
D:\tool\lua\bin\lua.cmd tests\glbs_test.lua
D:\tool\lua\bin\lua.cmd tests\iot_test.lua
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua
D:\tool\lua\bin\lua.cmd tests\app_alarm_test.lua
D:\tool\lua\bin\lua.cmd tests\app_algorithm_test.lua
D:\tool\lua\bin\lua.cmd tests\app_sms_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua
D:\tool\lua\bin\lua.cmd tests\main_test.lua
```

- [ ] **Step 2: Review diff and prepare merge back to local `main`**

```bash
git status --short
git diff --stat
```
