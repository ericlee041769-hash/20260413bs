local calls = {}
local errors = {}

_G.log = {
	error = function(...)
		errors[#errors + 1] = { ... }
	end
}

_G.adc = {
	ADC_RANGE_MIN = 11,
	ADC_RANGE_MAX = 22,
	CH_VBAT = 99,
	_open_ok = true,
	_get_value = 0,
	_read_raw = 0,
	_read_mv = 0,
	setRange = function(range)
		calls[#calls + 1] = { fn = "setRange", range = range }
	end,
	open = function(id)
		calls[#calls + 1] = { fn = "open", id = id }
		return adc._open_ok
	end,
	get = function(id)
		calls[#calls + 1] = { fn = "get", id = id }
		return adc._get_value
	end,
	read = function(id)
		calls[#calls + 1] = { fn = "read", id = id }
		return adc._read_raw, adc._read_mv
	end,
	close = function(id)
		calls[#calls + 1] = { fn = "close", id = id }
	end
}

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_nil(value, message)
	if value ~= nil then
		error(string.format("%s: expected nil, got %s", message, tostring(value)))
	end
end

local function clear_records()
	calls = {}
	errors = {}
	adc._open_ok = true
	adc._get_value = 0
	adc._read_raw = 0
	adc._read_mv = 0
end

local module_loader, load_err = loadfile("gadc.lua")
assert(module_loader, load_err)
local gadc = module_loader()

assert_equal(gadc.ADC0, 0, "ADC0 constant")
assert_equal(gadc.BATTERY_EMPTY_MV, 3300, "BATTERY_EMPTY_MV constant")
assert_equal(gadc.BATTERY_FULL_MV, 4200, "BATTERY_FULL_MV constant")

assert_equal(gadc.battery_percent_from_mv(3200), 0, "battery percent low clamp")
assert_equal(gadc.battery_percent_from_mv(3300), 0, "battery percent empty")
assert_equal(gadc.battery_percent_from_mv(3750), 50, "battery percent middle")
assert_equal(gadc.battery_percent_from_mv(4200), 100, "battery percent full")
assert_equal(gadc.battery_percent_from_mv(4300), 100, "battery percent high clamp")

clear_records()
adc._get_value = 3750
local battery_mv, battery_percent = gadc.read_battery()
assert_equal(battery_mv, 3750, "read_battery mv")
assert_equal(battery_percent, 50, "read_battery percent")
assert_equal(#calls, 3, "read_battery call count")
assert_equal(calls[1].fn, "open", "read_battery open fn")
assert_equal(calls[1].id, adc.CH_VBAT, "read_battery open id")
assert_equal(calls[2].fn, "get", "read_battery get fn")
assert_equal(calls[2].id, adc.CH_VBAT, "read_battery get id")
assert_equal(calls[3].fn, "close", "read_battery close fn")
assert_equal(calls[3].id, adc.CH_VBAT, "read_battery close id")

clear_records()
adc._open_ok = false
local failed_mv, failed_percent = gadc.read_battery()
assert_nil(failed_mv, "read_battery open fail mv")
assert_nil(failed_percent, "read_battery open fail percent")
assert_equal(#calls, 1, "read_battery open fail call count")
assert_equal(#errors, 1, "read_battery open fail log count")

clear_records()
adc._get_value = -1
local invalid_mv, invalid_percent = gadc.read_battery()
assert_nil(invalid_mv, "read_battery invalid mv")
assert_nil(invalid_percent, "read_battery invalid percent")
assert_equal(#calls, 3, "read_battery invalid call count")
assert_equal(#errors, 1, "read_battery invalid log count")

clear_records()
adc._read_raw = 123
adc._read_mv = 1100
local raw_value, adc_mv, sensor_mv = gadc.read_wcs1500_adc0()
assert_equal(raw_value, 123, "read_wcs1500_adc0 raw")
assert_equal(adc_mv, 1100, "read_wcs1500_adc0 adc mv")
assert_equal(sensor_mv, 2200, "read_wcs1500_adc0 sensor mv")
assert_equal(#calls, 4, "read_wcs1500_adc0 call count")
assert_equal(calls[1].fn, "setRange", "read_wcs1500_adc0 setRange fn")
assert_equal(calls[1].range, adc.ADC_RANGE_MIN, "read_wcs1500_adc0 setRange value")
assert_equal(calls[2].fn, "open", "read_wcs1500_adc0 open fn")
assert_equal(calls[2].id, gadc.ADC0, "read_wcs1500_adc0 open id")
assert_equal(calls[3].fn, "read", "read_wcs1500_adc0 read fn")
assert_equal(calls[3].id, gadc.ADC0, "read_wcs1500_adc0 read id")
assert_equal(calls[4].fn, "close", "read_wcs1500_adc0 close fn")
assert_equal(calls[4].id, gadc.ADC0, "read_wcs1500_adc0 close id")

clear_records()
adc._open_ok = false
local failed_raw, failed_adc_mv, failed_sensor_mv = gadc.read_wcs1500_adc0()
assert_nil(failed_raw, "read_wcs1500_adc0 open fail raw")
assert_nil(failed_adc_mv, "read_wcs1500_adc0 open fail adc mv")
assert_nil(failed_sensor_mv, "read_wcs1500_adc0 open fail sensor mv")
assert_equal(#calls, 2, "read_wcs1500_adc0 open fail call count")
assert_equal(#errors, 1, "read_wcs1500_adc0 open fail log count")

clear_records()
adc._read_raw = 55
adc._read_mv = -1
local invalid_raw, invalid_adc_mv, invalid_sensor_mv = gadc.read_wcs1500_adc0()
assert_nil(invalid_raw, "read_wcs1500_adc0 invalid raw")
assert_nil(invalid_adc_mv, "read_wcs1500_adc0 invalid adc mv")
assert_nil(invalid_sensor_mv, "read_wcs1500_adc0 invalid sensor mv")
assert_equal(#calls, 4, "read_wcs1500_adc0 invalid call count")
assert_equal(#errors, 1, "read_wcs1500_adc0 invalid log count")

print("gadc_test.lua: PASS")
