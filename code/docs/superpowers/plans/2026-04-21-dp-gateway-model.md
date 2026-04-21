# DP Gateway Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adapt MQTT payloads and replies to the third-party gateway DP field model while preserving the current internal snapshot and config model.

**Architecture:** Add a gateway-facing DP mapping layer at the MQTT boundary. Keep `app_collect.lua`, `app_alarm.lua`, and `app_config.lua` internally stable, and translate between external fields like `phonenum` / `tempdiff` / `lpoint` and internal fields like `alarm_sms_phone` / `temp_hum` / `location`.

**Tech Stack:** Lua, LuatOS MQTT transport, existing `gmqtt.lua` / `iot.lua`, script-style Lua tests with fake globals, local Lua runtime at `D:\tool\lua\bin\lua.cmd`

---

### Task 1: Add failing tests for the gateway-facing DP view

**Files:**
- Modify: `tests/gmqtt_test.lua`

- [ ] **Step 1: Add assertions for external DP names**

```lua
assert(published_dp[1].temp == 25.2, "published dp should expose temp")
assert(published_dp[1].temp2 == 26.8, "published dp should expose temp2")
assert(published_dp[1].phonenum == "15025376653", "published dp should expose phonenum")
assert(get_replies[1].dp.phonenum == "15025376653", "dp/get should expose phonenum")
assert(set_replies[1].dp.phonenum == "13800138000", "dp/set reply should echo phonenum")
```

- [ ] **Step 2: Run `tests/gmqtt_test.lua` and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua`  
Expected: FAIL because `gmqtt.lua` still publishes the internal snapshot shape.

### Task 2: Implement the DP mapping at the MQTT boundary

**Files:**
- Modify: `gmqtt.lua`
- Modify: `iot.lua`

- [ ] **Step 1: Add a gateway DP builder in `gmqtt.lua`**

```lua
local function build_gateway_dp(cfg, latest, latest_alarm)
	return {
		temp = ...,
		door = ...,
		humidity = ...,
		err = ...,
		time = ...,
		phonenum = ...,
		temp2 = ...,
		humidity2 = ...,
		tempdiff = ...,
		lpoint = ...
	}
end
```

- [ ] **Step 2: Make `dp/get` and `dp/post` use the gateway DP view**

```lua
local gateway_dp = build_gateway_dp(current_config(), snapshot, current_alarm())
return iot.publish_dp(gateway_dp)
```

- [ ] **Step 3: Update `iot.publish_dp()` to omit `deviceId` for direct MQTT post**

```lua
local payload = {
	dp = dp
}
```

- [ ] **Step 4: Run `tests/gmqtt_test.lua` and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua`  
Expected: PASS

### Task 3: Restrict `dp/set` to `phonenum` only

**Files:**
- Modify: `gmqtt.lua`
- Modify: `tests/gmqtt_test.lua`

- [ ] **Step 1: Add a failing ignore-write assertion**

```lua
assert(set_replies[2].dp.temp == nil, "dp/set should ignore temp writes")
assert(set_replies[2].dp.phonenum == nil, "dp/set should return empty dp when nothing is accepted")
```

- [ ] **Step 2: Implement the external-to-internal set mapping**

```lua
local function apply_set_dp(dp)
	local changes = {}
	if type(dp.phonenum) == "string" then
		changes.alarm_sms_phone = dp.phonenum
	end
	local applied = app_config.update(changes)
	return {
		phonenum = applied.alarm_sms_phone
	}
end
```

- [ ] **Step 3: Run `tests/gmqtt_test.lua` and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua`  
Expected: PASS

### Task 4: Run full regression and merge back

**Files:**
- Test: `tests/io_test.lua`
- Test: `tests/gadc_test.lua`
- Test: `tests/gsht30_test.lua`
- Test: `tests/gbaro_test.lua`
- Test: `tests/glbs_test.lua`
- Test: `tests/app_config_test.lua`
- Test: `tests/app_state_test.lua`
- Test: `tests/app_collect_test.lua`
- Test: `tests/app_alarm_test.lua`
- Test: `tests/app_sms_test.lua`
- Test: `tests/application_test.lua`
- Test: `tests/gmqtt_test.lua`
- Test: `tests/main_test.lua`

- [ ] **Step 1: Run the full Lua test set**

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\gadc_test.lua
D:\tool\lua\bin\lua.cmd tests\gsht30_test.lua
D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua
D:\tool\lua\bin\lua.cmd tests\glbs_test.lua
D:\tool\lua\bin\lua.cmd tests\app_config_test.lua
D:\tool\lua\bin\lua.cmd tests\app_state_test.lua
D:\tool\lua\bin\lua.cmd tests\app_collect_test.lua
D:\tool\lua\bin\lua.cmd tests\app_alarm_test.lua
D:\tool\lua\bin\lua.cmd tests\app_sms_test.lua
D:\tool\lua\bin\lua.cmd tests\application_test.lua
D:\tool\lua\bin\lua.cmd tests\gmqtt_test.lua
D:\tool\lua\bin\lua.cmd tests\main_test.lua
```

- [ ] **Step 2: Merge back to local `main` after verification**

```bash
git checkout main
git merge --no-ff dp-gateway-model
```
