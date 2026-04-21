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

local send_calls = {}

_G.sms = {
	sendLong = function(phone, text, auto_fix)
		send_calls[#send_calls + 1] = {
			phone = phone,
			text = text,
			auto_fix = auto_fix
		}
		return {
			wait = function()
				return true
			end
		}
	end,
	setNewSmsCb = function()
		error("setNewSmsCb should not be used")
	end
}

_G.sys = {
	subscribe = function(event_name)
		error("sys.subscribe should not be used for " .. tostring(event_name))
	end
}

_G.log = {
	info = function() end,
	error = function() end
}

local loader, load_err = loadfile("app_sms.lua")
assert(loader, load_err)
local app_sms = loader()

assert_false(app_sms.send_alert("13800138000", "告警:测试"), "send_alert should skip before ready")
assert_equal(#send_calls, 0, "send_alert should not call sms before ready")

app_sms.set_ready(true)

local ok = app_sms.send_alert("13800138000", "告警:测试")
assert_true(ok, "send_alert should return wait result")
assert_equal(send_calls[1].phone, "13800138000", "send_alert should use provided phone")
assert_equal(send_calls[1].text, "告警:测试", "send_alert should use provided text")
assert_true(send_calls[1].auto_fix, "send_alert should enable phone auto-fix")

_G.sms.sendLong = function(phone, text, auto_fix)
	send_calls[#send_calls + 1] = {
		phone = phone,
		text = text,
		auto_fix = auto_fix
	}
	return {
		wait = function()
			return false
		end
	}
end

assert_false(app_sms.send_alert("13800138000", "告警:失败路径"), "failed wait should return false")
app_sms.set_ready(false)
assert_false(app_sms.send_alert("13800138000", "告警:再次跳过"), "send_alert should skip after ready reset")
assert_false(app_sms.send_alert("", "告警:空号码"), "empty phone should fail")
assert_false(app_sms.send_alert("13800138000", ""), "empty text should fail")

print("app_sms_test.lua: PASS")
