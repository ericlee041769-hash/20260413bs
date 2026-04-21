# Power Mode VBUS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GPIO21-based VBUS detection and use it to switch between USB always-on behavior and battery low-power scheduling with pre-wakeup.

**Architecture:** Extend `ggpio.lua` with one VBUS input reader, add `app_power.lua` as the sole power-mode and PM boundary, then update `application.lua` so the existing shared business processing flow runs under a mode-dependent scheduler. Keep `config.lua` as the single configuration definition entrypoint and preserve the current alarm/MQTT path.

**Tech Stack:** Lua, LuatOS GPIO and PM APIs, existing `application.lua` / `ggpio.lua` / `app_config.lua`, script-style Lua tests with fake globals, local Lua runtime at `D:\tool\lua\bin\lua.cmd`

---

### Task 1: Add failing tests for GPIO21 VBUS detection

**Files:**
- Modify: `tests/io_test.lua`

- [ ] **Step 1: Add a failing VBUS-input test**

```lua
assert_equal(io_ctrl.GPIO21_VBUS, 21, "GPIO21_VBUS constant")
assert_equal(calls[10].pin, io_ctrl.GPIO21_VBUS, "vbus setup pin")
assert_true(io_ctrl.get_usb_power_state(), "high vbus level should mean usb present")
```

- [ ] **Step 2: Run the GPIO test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\io_test.lua`  
Expected: FAIL because `ggpio.lua` does not yet expose `GPIO21_VBUS` or `get_usb_power_state()`.

### Task 2: Add failing tests for the power-mode module

**Files:**
- Create: `tests/app_power_test.lua`

- [ ] **Step 1: Write the failing mode/profile tests**

```lua
local profile = app_power.current_profile({
	usb_sample_interval_ms = 10000,
	usb_report_interval_ms = 10000,
	battery_sample_interval_ms = 60000,
	battery_report_interval_ms = 60000,
	battery_prewake_ms = 5000
})

assert_equal(profile.mode, "USB", "vbus high should select usb mode")
assert_equal(profile.sample_interval_ms, 10000, "usb sample interval")
assert_equal(profile.report_interval_ms, 10000, "usb report interval")
```

- [ ] **Step 2: Run the power test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\app_power_test.lua`  
Expected: FAIL because `app_power.lua` does not exist yet.

### Task 3: Implement `ggpio.lua` VBUS input and `app_power.lua`

**Files:**
- Modify: `ggpio.lua`
- Modify: `config.lua`
- Create: `app_power.lua`
- Modify: `tests/app_config_test.lua`

- [ ] **Step 1: Add the runtime config fields for USB/battery mode**

```lua
usb_sample_interval_ms = 10000,
usb_report_interval_ms = 10000,
battery_sample_interval_ms = 60000,
battery_report_interval_ms = 60000,
battery_prewake_ms = 5000
```

- [ ] **Step 2: Add `GPIO21` VBUS input handling to `ggpio.lua`**

```lua
io_ctrl.GPIO21_VBUS = 21
vbus_input_reader = gpio.setup(io_ctrl.GPIO21_VBUS, nil, gpio.PULLDOWN)

function io_ctrl.get_usb_power_state()
	if type(vbus_input_reader) ~= "function" then
		return nil
	end
	return normalize_level(vbus_input_reader()) ~= 0
end
```

- [ ] **Step 3: Implement `app_power.lua`**

```lua
function app_power.current_mode(cfg)
	local usb_present = ggpio.get_usb_power_state()
	if usb_present == nil then
		return "USB"
	end
	return usb_present and "USB" or "BATTERY"
end
```

- [ ] **Step 4: Run the targeted tests and verify they pass**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_power_test.lua
```

Expected: PASS

### Task 4: Add failing application tests for USB and battery scheduling

**Files:**
- Modify: `tests/application_test.lua`

- [ ] **Step 1: Add a failing USB-mode assertion**

```lua
assert_equal(wait_calls[1], 10000, "usb mode should wait the usb sample interval")
assert_equal(pm_sleep_calls, 0, "usb mode should not sleep")
```

- [ ] **Step 2: Add a failing battery-mode assertion**

```lua
assert_equal(wakeup_calls[1], 55000, "battery mode should schedule interval minus prewake")
assert_equal(pm_sleep_calls, 1, "battery mode should enter sleep after the cycle")
```

- [ ] **Step 3: Run the application test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\application_test.lua`  
Expected: FAIL because `application.lua` still uses the old single-mode `sample_interval_ms` loop.

### Task 5: Implement mode-aware scheduling in `application.lua`

**Files:**
- Modify: `application.lua`

- [ ] **Step 1: Require `app_power.lua` and replace the old generic interval fields with mode profiles**

```lua
local profile = app_power.current_profile(cfg)
```

- [ ] **Step 2: Keep one shared process helper and make the post-cycle scheduler mode-aware**

```lua
if profile.mode == "USB" then
	sys.wait(profile.sample_interval_ms)
else
	app_power.prepare_next_wakeup(cfg)
	app_power.enter_sleep()
end
```

- [ ] **Step 3: Use the profile report interval for MQTT due checks**

```lua
if force_report or last_report_ms == 0 or (now_ms() - last_report_ms) >= profile.report_interval_ms then
```

- [ ] **Step 4: Run the targeted tests and verify they pass**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\app_power_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
```

Expected: PASS

### Task 6: Run full regression

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
- Test: `tests\app_power_test.lua`
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
D:\tool\lua\bin\lua.cmd tests\app_power_test.lua
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
