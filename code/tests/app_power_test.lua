local fake_ggpio = {
	get_usb_power_state = function()
		return true
	end
}

local original_require = _G.require
local errors = {}
local info_logs = {}

_G.log = {
	error = function(...)
		errors[#errors + 1] = { ... }
	end,
	info = function(...)
		info_logs[#info_logs + 1] = { ... }
	end
}

_G.require = function(name)
	if name == "ggpio" then
		return fake_ggpio
	end
	return original_require(name)
end

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

local cfg = {
	usb_sample_interval_ms = 10000,
	usb_report_interval_ms = 10000,
	battery_sample_interval_ms = 60000,
	battery_report_interval_ms = 60000,
	battery_prewake_ms = 5000
}

local loader, load_err = loadfile("app_power.lua")
assert(loader, load_err)
local app_power = loader()

local usb_profile = app_power.current_profile(cfg)
assert_equal(usb_profile.mode, "USB", "vbus high should select usb mode")
assert_equal(usb_profile.sample_interval_ms, 10000, "usb sample interval")
assert_equal(usb_profile.report_interval_ms, 10000, "usb report interval")
assert_equal(usb_profile.prewake_ms, 0, "usb prewake should be zero")
assert_false(app_power.should_sleep_after_cycle(cfg), "usb mode should not sleep after cycle")

fake_ggpio.get_usb_power_state = function()
	return false
end

local battery_profile = app_power.current_profile(cfg)
assert_equal(battery_profile.mode, "BATTERY", "vbus low should select battery mode")
assert_equal(battery_profile.sample_interval_ms, 60000, "battery sample interval")
assert_equal(battery_profile.report_interval_ms, 60000, "battery report interval")
assert_equal(battery_profile.prewake_ms, 5000, "battery prewake")
assert_true(app_power.should_sleep_after_cycle(cfg), "battery mode should sleep after cycle")
assert_equal(app_power.next_wakeup_delay_ms(cfg), 55000, "battery next wakeup should subtract prewake")

fake_ggpio.get_usb_power_state = function()
	return nil
end

local fallback_profile = app_power.current_profile(cfg)
assert_equal(fallback_profile.mode, "USB", "vbus detection failure should fall back to usb mode")
assert_equal(#errors, 1, "vbus detection failure should log once")

_G.require = original_require

print("app_power_test.lua: PASS")
