local fake_store = {}
local original_require = _G.require

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_nil(actual, message)
	if actual ~= nil then
		error(string.format("%s: expected nil, got %s", message, tostring(actual)))
	end
end

local fake_config = {
	MQTT = {},
	RUNTIME_DEFAULTS = {
		sample_interval_ms = 10000,
		report_interval_ms = 10000,
		usb_sample_interval_ms = 10000,
		usb_report_interval_ms = 10000,
		battery_sample_interval_ms = 60000,
		battery_report_interval_ms = 60000,
		battery_prewake_ms = 5000,
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
	},
	RUNTIME_FIELD_TYPES = {
		sample_interval_ms = "number",
		report_interval_ms = "number",
		usb_sample_interval_ms = "number",
		usb_report_interval_ms = "number",
		battery_sample_interval_ms = "number",
		battery_report_interval_ms = "number",
		battery_prewake_ms = "number",
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
	},
	RUNTIME_MUTABLE_FIELDS = {
		sample_interval_ms = true,
		report_interval_ms = true,
		usb_sample_interval_ms = true,
		usb_report_interval_ms = true,
		battery_sample_interval_ms = true,
		battery_report_interval_ms = true,
		battery_prewake_ms = true,
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
}

_G.fskv = {
	get = function(key)
		return fake_store[key]
	end,
	set = function(key, value)
		fake_store[key] = value
		return true
	end
}

_G.log = {
	error = function() end
}

_G.require = function(name)
	if name == "config" then
		return fake_config
	end
	return original_require(name)
end

local config_loader, load_err = loadfile("app_config.lua")
assert(config_loader, load_err)
local app_config = config_loader()

local cfg = app_config.load()
assert_equal(cfg.sample_interval_ms, 10000, "default sample interval")
assert_equal(cfg.report_interval_ms, 10000, "default report interval")
assert_equal(cfg.usb_sample_interval_ms, 10000, "default usb sample interval")
assert_equal(cfg.battery_sample_interval_ms, 60000, "default battery sample interval")
assert_equal(cfg.battery_prewake_ms, 5000, "default battery prewake")
assert_equal(cfg.airlbs_timeout, 10000, "default airlbs timeout")
assert_equal(cfg.temp_diff_high, 5, "default temp diff high")
assert_equal(cfg.alarm_sms_phone, "15025376653", "default alarm sms phone")

local updated = app_config.update({
	report_interval_ms = 15000,
	battery_prewake_ms = 8000,
	temp_high = 60,
	temp_diff_high = 6,
	alarm_sms_phone = "13800138000",
	unknown_key = 1,
	current_low = "bad",
	MQTT = {}
})
assert_equal(updated.report_interval_ms, 15000, "updated report interval")
assert_equal(updated.battery_prewake_ms, 8000, "updated battery prewake")
assert_equal(updated.temp_high, 60, "updated temp high")
assert_equal(updated.temp_diff_high, 6, "updated temp diff high")
assert_equal(updated.alarm_sms_phone, "13800138000", "updated alarm sms phone")
assert_nil(updated.unknown_key, "unknown key should be ignored")
assert_nil(updated.current_low, "wrong type should be ignored")
assert_nil(updated.MQTT, "static config should not be mutable")

local reloaded = app_config.load()
assert_equal(reloaded.report_interval_ms, 15000, "persisted report interval")
assert_equal(reloaded.battery_prewake_ms, 8000, "persisted battery prewake")
assert_equal(reloaded.temp_high, 60, "persisted temp high")
assert_equal(reloaded.current_low, 0, "invalid current low should not persist")
assert_equal(reloaded.temp_diff_high, 6, "persisted temp diff high")
assert_equal(reloaded.alarm_sms_phone, "13800138000", "persisted alarm sms phone")

_G.require = original_require

print("app_config_test.lua: PASS")
