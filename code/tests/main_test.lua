local required_modules = {}
local task_queue = {}
local gpio_calls = {}
local ggpio_calls = {}
local gadc_calls = {}
local gsht30_calls = {}
local gmqtt_calls = {}
local run_called = false
local wait_calls = {}
local stop_after_wait_err = "STOP_AFTER_WAIT"

local fake_sys = {
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	run = function()
		run_called = true
	end,
	wait = function(ms)
		wait_calls[#wait_calls + 1] = ms
		if #wait_calls >= 2 then
			error(stop_after_wait_err)
		end
	end,
	waitUntil = function()
		return false
	end
}

local fake_ggpio = {
	init = function()
		ggpio_calls[#ggpio_calls + 1] = { fn = "init" }
		return true
	end,
	set_adc = function(level)
		ggpio_calls[#ggpio_calls + 1] = { fn = "set_adc", level = level }
		return true
	end,
	set_3v3 = function(level)
		ggpio_calls[#ggpio_calls + 1] = { fn = "set_3v3", level = level }
		return true
	end,
	set_5v = function(level)
		ggpio_calls[#ggpio_calls + 1] = { fn = "set_5v", level = level }
		return true
	end,
	set_gpio28 = function(level)
		ggpio_calls[#ggpio_calls + 1] = { fn = "set_gpio28", level = level }
		return true
	end
}

local fake_gadc = {
	read_battery = function()
		gadc_calls[#gadc_calls + 1] = { fn = "read_battery" }
		return 3800, 56
	end,
	read_wcs1500_adc0 = function()
		gadc_calls[#gadc_calls + 1] = { fn = "read_wcs1500_adc0" }
		return 1234, 500, 1000
	end
}

local fake_gmqtt = {
	start = function(device_props)
		gmqtt_calls[#gmqtt_calls + 1] = device_props
		return true
	end
}

local fake_gsht30 = {
	I2C0 = 0,
	I2C1 = 1,
	init = function()
		gsht30_calls[#gsht30_calls + 1] = { fn = "init" }
		return true
	end,
	read_all = function()
		gsht30_calls[#gsht30_calls + 1] = { fn = "read_all" }
		return {
			[0] = { ok = true, humidity = 501, temperature = 252 },
			[1] = { ok = true, humidity = 603, temperature = 268 }
		}
	end
}

local fake_modules = {
	sys = fake_sys,
	config = {
		MQTT = {
			getTopic = "get/topic",
			setTopic = "set/topic"
		}
	},
	application = {},
	ggpio = fake_ggpio,
	gadc = fake_gadc,
	gsht30 = fake_gsht30,
	gmqtt = fake_gmqtt
}

local env = {
	_G = nil,
	PROJECT = nil,
	VERSION = nil,
	require = function(name)
		required_modules[name] = true
		local mod = fake_modules[name]
		assert(mod, "unexpected require: " .. tostring(name))
		return mod
	end,
	gpio = {
		setup = function(pin, level)
			gpio_calls[#gpio_calls + 1] = { fn = "setup", pin = pin, level = level }
		end,
		set = function(pin, level)
			gpio_calls[#gpio_calls + 1] = { fn = "set", pin = pin, level = level }
		end
	},
	log = {
		info = function() end,
		error = function() end
	},
	json = {
		decode = function()
			return {}
		end,
		encode = function()
			return "{}"
		end
	},
	os = {
		date = function()
			return "2026-04-17 10:00:00"
		end,
		time = function()
			return 1
		end
	},
	math = {
		randomseed = function() end,
		random = function()
			return 1
		end
	}
}

env._G = env
setmetatable(env, { __index = _G })

local chunk, load_err = loadfile("main.lua", "t", env)
assert(chunk, load_err)
chunk()

assert(required_modules.ggpio, "main.lua should require ggpio")
assert(required_modules.gadc, "main.lua should require gadc")
assert(required_modules.gsht30, "main.lua should require gsht30")
assert(required_modules.gmqtt, "main.lua should require gmqtt")
assert(run_called, "main.lua should call sys.run")
assert(#task_queue == 2, "main.lua should register two local background tasks")
assert(#ggpio_calls == 1, "main.lua should init ggpio once at startup")
assert(ggpio_calls[1].fn == "init", "startup ggpio call should be init")
assert(#gmqtt_calls == 1, "main.lua should call gmqtt.start once")
assert(type(gmqtt_calls[1]) == "table", "gmqtt.start should receive device props")
assert(gmqtt_calls[1].sn == "AIR780EPM-SN-001", "device props sn should match")

local ok, run_err = pcall(task_queue[1])
assert(not ok, "first task should be stopped by fake sys.wait")
assert(string.find(run_err, stop_after_wait_err, 1, true), "first task should stop on fake wait guard")
assert(#gadc_calls == 4, "gadc task should read battery and adc twice")
assert(gadc_calls[1].fn == "read_battery", "first gadc call should read battery")
assert(gadc_calls[2].fn == "read_wcs1500_adc0", "second gadc call should read adc0")
assert(gadc_calls[3].fn == "read_battery", "third gadc call should read battery")
assert(gadc_calls[4].fn == "read_wcs1500_adc0", "fourth gadc call should read adc0")
assert(#wait_calls == 2, "gadc task should wait twice")
assert(wait_calls[1] == 1000, "first gadc wait should be 1000ms")
assert(wait_calls[2] == 1000, "second gadc wait should be 1000ms")

wait_calls = {}
local ok2, run_err2 = pcall(task_queue[2])
assert(not ok2, "second task should be stopped by fake sys.wait")
assert(string.find(run_err2, stop_after_wait_err, 1, true), "second task should stop on fake wait guard")
assert(#gsht30_calls == 3, "gsht30 task should init once and read twice")
assert(gsht30_calls[1].fn == "init", "gsht30 first call should be init")
assert(gsht30_calls[2].fn == "read_all", "gsht30 second call should be read_all")
assert(gsht30_calls[3].fn == "read_all", "gsht30 third call should be read_all")
assert(#wait_calls == 2, "gsht30 task should wait twice")
assert(wait_calls[1] == 1000, "first gsht30 wait should be 1000ms")
assert(wait_calls[2] == 1000, "second gsht30 wait should be 1000ms")

print("main_test.lua: PASS")
