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

local function assert_contains(text, expected, message)
	if not string.find(text, expected, 1, true) then
		error(message .. ": missing " .. expected)
	end
end

local loader, load_err = loadfile("app_alarm.lua")
assert(loader, load_err)
local app_alarm = loader()

local cfg = {
	temp_low = -40,
	temp_high = 85,
	temp_diff_high = 5,
	current_low = 0,
	current_high = 50000,
	pressure_diff_low = 1.0,
	pressure_diff_high = 1.5,
	door_open_warn_ms = 5000
}

local alarm_snapshot = {
	timestamp = "2026-04-21 16:00:00",
	current_sensor_mv = 53000,
	door_open = true,
	temp_hum = {
		[0] = { ok = true, temperature = 86.2, humidity = 50.0 },
		[1] = { ok = true, temperature = 80.0, humidity = 51.0 }
	},
	pressure = {
		[1] = { ok = true, pressure = 100.0 },
		[2] = { ok = true, pressure = 100.7 }
	}
}

local healthy_snapshot = {
	timestamp = "2026-04-21 16:01:00",
	current_sensor_mv = 20000,
	door_open = false,
	temp_hum = {
		[0] = { ok = true, temperature = 25.0, humidity = 50.0 },
		[1] = { ok = true, temperature = 27.0, humidity = 51.0 }
	},
	pressure = {
		[1] = { ok = true, pressure = 100.0 },
		[2] = { ok = true, pressure = 101.2 }
	}
}

local first = app_alarm.evaluate(cfg, alarm_snapshot, {
	active_map = {},
	door_open_since_ms = 1000
}, 7000)

assert_true(first.should_send_sms, "new alarms should request sms")
assert_true(first.active_map.door_open_timeout, "door timeout should be active")
assert_true(first.active_map.temp1_high, "temp1 high should be active")
assert_true(first.active_map.temp_diff_high, "temp delta should be active")
assert_true(first.active_map.current_high, "current high should be active")
assert_true(first.active_map.pressure_diff_low, "pressure diff low should be active")
assert_equal(#first.new_alarm_keys, 5, "should report five new alarms")
assert_equal(first.sms_text,
	"告警:门持续打开超时; 温度1高温=86.2; 温差异常=6.2; 电流高=53000; 压差异常=0.7; 时间=2026-04-21 16:00:00",
	"merged sms text should be stable")
assert_equal(first.err_text,
	"门持续打开超时; 温度1高温=86.2; 温差异常=6.2; 电流高=53000; 压差异常=0.7",
	"active alarm text should describe current causes")

local second = app_alarm.evaluate(cfg, alarm_snapshot, first.runtime, 8000)
assert_false(second.should_send_sms, "same active alarm should not resend")
assert_equal(second.sms_text, "", "no resend should produce empty sms text")
assert_equal(second.err_text,
	"门持续打开超时; 温度1高温=86.2; 温差异常=6.2; 电流高=53000; 压差异常=0.7",
	"active alarm text should stay available during sustained alarm")

local recovered = app_alarm.evaluate(cfg, healthy_snapshot, second.runtime, 9000)
assert_false(recovered.should_send_sms, "recovery should not send sms")
assert_equal(next(recovered.active_map), nil, "recovery should clear active alarms")
assert_equal(recovered.err_text, "正常", "recovery should report normal status")

local third = app_alarm.evaluate(cfg, alarm_snapshot, recovered.runtime, 16000)
assert_true(third.should_send_sms, "alarm should resend after recovery")
assert_contains(third.sms_text, "温度1高温=86.2", "retrigger sms should include temp segment")
assert_contains(third.err_text, "温度1高温=86.2", "retrigger err text should include temp segment")

print("app_alarm_test.lua: PASS")
