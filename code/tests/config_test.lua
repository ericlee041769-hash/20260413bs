local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local loader, load_err = loadfile("config.lua")
assert(loader, load_err)
local config = loader()

assert_equal(config.RUNTIME_DEFAULTS.airlbs_project_id, "lvU4QJ", "default airlbs project id")
assert_equal(config.RUNTIME_DEFAULTS.airlbs_project_key, "hbHtgCRY8OUvCqEC3NEyLZb5CS0w7oHV", "default airlbs project key")
assert_equal(config.RUNTIME_DEFAULTS.usb_interval_ms, 10000, "default usb interval")
assert_equal(config.RUNTIME_DEFAULTS.battery_interval_ms, 60000, "default battery interval")
assert_equal(config.GATEWAY_CONFIG_FIELDS.usb_interval_ms, true, "gateway config should include usb interval")
assert_equal(config.GATEWAY_CONFIG_FIELDS.battery_interval_ms, true, "gateway config should include battery interval")
assert_equal(config.GATEWAY_CONFIG_FIELDS.alarm_sms_phone, true, "gateway config should include alarm sms phone")
assert_equal(config.GATEWAY_CONFIG_FIELDS.airlbs_project_id, nil, "gateway config should exclude airlbs project id")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.airlbs_project_id, true, "airlbs project id should stay mutable")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.airlbs_project_key, true, "airlbs project key should stay mutable")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.usb_interval_ms, true, "usb interval should stay mutable")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.battery_interval_ms, true, "battery interval should stay mutable")
assert_equal(config.RUNTIME_DEFAULTS.sample_interval_ms, nil, "legacy sample interval should be removed")
assert_equal(config.RUNTIME_DEFAULTS.report_interval_ms, nil, "legacy report interval should be removed")
assert_equal(config.RUNTIME_DEFAULTS.usb_sample_interval_ms, nil, "legacy usb sample interval should be removed")
assert_equal(config.RUNTIME_DEFAULTS.usb_report_interval_ms, nil, "legacy usb report interval should be removed")
assert_equal(config.RUNTIME_DEFAULTS.battery_sample_interval_ms, nil, "legacy battery sample interval should be removed")
assert_equal(config.RUNTIME_DEFAULTS.battery_report_interval_ms, nil, "legacy battery report interval should be removed")

print("config_test.lua: PASS")
