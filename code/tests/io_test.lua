local calls = {}
local errors = {}
local infos = {}
local published = {}

_G.gpio = {
	WAKEUP0 = 101,
	PULLDOWN = 202,
	PULLUP = 201,
	BOTH = 250,
	FALLING = 301,
	_input_levels = {
		[101] = 0,
		[21] = 1
	},
	setup = function(pin, level, pull, irq)
		calls[#calls + 1] = {
			fn = "setup",
			pin = pin,
			level = level,
			pull = pull,
			irq = irq
		}

		if type(level) == "function" or level == nil then
			return function()
				return gpio._input_levels[pin] or 0
			end
		end
	end,
	set = function(pin, level)
		calls[#calls + 1] = { fn = "set", pin = pin, level = level }
	end
}

_G.log = {
	info = function(...)
		infos[#infos + 1] = { ... }
	end,
	error = function(...)
		errors[#errors + 1] = { ... }
	end
}

_G.sys = {
	wait = function() end,
	publish = function(name, ...)
		published[#published + 1] = {
			name = name,
			args = { ... }
		}
	end
}

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

local function clear_records()
	calls = {}
	errors = {}
	infos = {}
	published = {}
end

local module_loader, load_err = loadfile("ggpio.lua")
assert(module_loader, load_err)
local io_ctrl = module_loader()

assert_equal(io_ctrl.GPIO_ADC_EN, 24, "GPIO_ADC_EN constant")
assert_equal(io_ctrl.GPIO_3V3_EN, 25, "GPIO_3V3_EN constant")
assert_equal(io_ctrl.GPIO_5V_EN, 27, "GPIO_5V_EN constant")
assert_equal(io_ctrl.GPIO_28, 28, "GPIO_28 constant")
assert_equal(io_ctrl.GPIO21_VBUS, 21, "GPIO21_VBUS constant")

clear_records()
assert_true(io_ctrl.init(), "init return")
local expected_pins = {
	io_ctrl.GPIO_ADC_EN,
	io_ctrl.GPIO_3V3_EN,
	io_ctrl.GPIO_5V_EN,
	io_ctrl.GPIO_28
}
assert_equal(#calls, 10, "init call count")
for i = 1, #expected_pins do
	local setup_call = calls[(i - 1) * 2 + 1]
	local set_call = calls[(i - 1) * 2 + 2]
	assert_equal(setup_call.fn, "setup", "setup function name " .. i)
	assert_equal(setup_call.pin, expected_pins[i], "setup pin " .. i)
	assert_equal(setup_call.level, 1, "setup level " .. i)
	assert_equal(set_call.fn, "set", "set function name " .. i)
	assert_equal(set_call.pin, expected_pins[i], "set pin " .. i)
	assert_equal(set_call.level, 1, "set level " .. i)
end
local vbus_setup_call = calls[9]
assert_equal(vbus_setup_call.fn, "setup", "vbus setup function name")
assert_equal(vbus_setup_call.pin, io_ctrl.GPIO21_VBUS, "vbus setup pin")
assert_equal(vbus_setup_call.level, nil, "vbus setup should use input mode")
assert_equal(vbus_setup_call.pull, gpio.PULLDOWN, "vbus setup pull mode")
assert_equal(vbus_setup_call.irq, nil, "vbus setup irq mode")
assert_true(io_ctrl.get_usb_power_state(), "initial vbus high should mean usb present")

local wakeup_setup_call = calls[10]
assert_equal(wakeup_setup_call.fn, "setup", "wakeup0 setup function name")
assert_equal(wakeup_setup_call.pin, gpio.WAKEUP0, "wakeup0 setup pin")
assert_equal(type(wakeup_setup_call.level), "function", "wakeup0 callback type")
assert_equal(wakeup_setup_call.pull, gpio.PULLUP, "wakeup0 pull mode")
assert_equal(wakeup_setup_call.irq, gpio.BOTH, "wakeup0 irq mode")
assert_false(io_ctrl.get_door_state(), "initial door state should be closed")

clear_records()
gpio._input_levels[io_ctrl.GPIO21_VBUS] = 0
assert_false(io_ctrl.get_usb_power_state(), "vbus low should mean battery mode")

clear_records()
gpio._input_levels[gpio.WAKEUP0] = 0
wakeup_setup_call.level(0, gpio.WAKEUP0)
assert_equal(#infos, 1, "wakeup0 callback should log once")
assert_equal(infos[1][1], "ggpio", "wakeup0 log tag")
assert_equal(infos[1][2], "门磁触发", "wakeup0 log message")
assert_equal(infos[1][3], gpio.WAKEUP0, "wakeup0 log pin")
assert_equal(infos[1][4], 0, "wakeup0 log level")
assert_equal(infos[1][5], "关闭", "wakeup0 log door state")
assert_equal(#published, 1, "wakeup0 callback should publish one edge event")
assert_equal(published[1].name, "APP_DOOR_EDGE", "wakeup0 callback should publish door edge event")
assert_equal(published[1].args[1], gpio.WAKEUP0, "wakeup0 event should publish pin")
assert_equal(published[1].args[2], 0, "wakeup0 event should publish level")
assert_false(io_ctrl.get_door_state(), "door state should become closed after low level callback")

clear_records()
gpio._input_levels[gpio.WAKEUP0] = 1
wakeup_setup_call.level(1, gpio.WAKEUP0)
assert_equal(#infos, 1, "second wakeup0 callback should log once")
assert_equal(infos[1][2], "门磁触发", "second wakeup0 log message")
assert_equal(infos[1][4], 1, "second wakeup0 log level")
assert_equal(infos[1][5], "打开", "second wakeup0 log door state")
assert_equal(#published, 1, "second wakeup0 callback should publish one edge event")
assert_equal(published[1].name, "APP_DOOR_EDGE", "second wakeup0 callback should publish door edge event")
assert_equal(published[1].args[2], 1, "second wakeup0 event should publish level")
assert_true(io_ctrl.get_door_state(), "door state should become open after high level callback")

clear_records()
assert_true(io_ctrl.set(io_ctrl.GPIO_ADC_EN, false), "set low return")
assert_equal(#calls, 1, "set low call count")
assert_equal(calls[1].fn, "set", "set low function name")
assert_equal(calls[1].pin, io_ctrl.GPIO_ADC_EN, "set low pin")
assert_equal(calls[1].level, 0, "set low level")
assert_equal(#infos, 1, "set low should log level change")
assert_equal(infos[1][1], "ggpio", "set low log tag")
assert_equal(infos[1][2], "level changed", "set low log message")
assert_equal(infos[1][3], io_ctrl.GPIO_ADC_EN, "set low log pin")
assert_equal(infos[1][4], 1, "set low previous level")
assert_equal(infos[1][5], 0, "set low current level")

clear_records()
assert_true(io_ctrl.set(io_ctrl.GPIO_5V_EN, 2), "set nonzero return")
assert_equal(#calls, 1, "set nonzero call count")
assert_equal(calls[1].level, 1, "set nonzero normalized level")
assert_equal(#infos, 0, "set nonzero without change should not log")

clear_records()
assert_true(io_ctrl.set(io_ctrl.GPIO_ADC_EN, 1), "set high return")
assert_equal(#calls, 1, "set high call count")
assert_equal(calls[1].level, 1, "set high normalized level")
assert_equal(#infos, 1, "set high should log level change")
assert_equal(infos[1][4], 0, "set high previous level")
assert_equal(infos[1][5], 1, "set high current level")

clear_records()
assert_true(io_ctrl.set_3v3(true), "set_3v3 return")
assert_equal(calls[1].pin, io_ctrl.GPIO_3V3_EN, "set_3v3 pin")
assert_equal(calls[1].level, 1, "set_3v3 level")

clear_records()
assert_true(io_ctrl.set_5v(false), "set_5v return")
assert_equal(calls[1].pin, io_ctrl.GPIO_5V_EN, "set_5v pin")
	assert_equal(calls[1].level, 0, "set_5v level")

clear_records()
assert_true(io_ctrl.set_adc(true), "set_adc return")
assert_equal(calls[1].pin, io_ctrl.GPIO_ADC_EN, "set_adc pin")
assert_equal(calls[1].level, 1, "set_adc level")

clear_records()
assert_true(io_ctrl.set_gpio28(false), "set_gpio28 return")
assert_equal(calls[1].pin, io_ctrl.GPIO_28, "set_gpio28 pin")
assert_equal(calls[1].level, 0, "set_gpio28 level")

clear_records()
assert_false(io_ctrl.set(26, 1), "invalid pin return")
assert_equal(#calls, 0, "invalid pin should not write gpio")
assert_equal(#errors, 1, "invalid pin should log once")

print("io_test.lua: PASS")
