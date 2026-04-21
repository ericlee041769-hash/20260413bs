local required_modules = {}
local app_start_calls = 0
local task_queue = {}
local run_called = false

local fake_sys = {
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	run = function()
		run_called = true
	end
}

local fake_application = {
	start = function()
		app_start_calls = app_start_calls + 1
		return true
	end
}

local fake_modules = {
	sys = fake_sys,
	config = {},
	application = fake_application
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
	log = {
		info = function() end,
		error = function() end
	}
}

env._G = env
setmetatable(env, { __index = _G })

local chunk, load_err = loadfile("main.lua", "t", env)
assert(chunk, load_err)
chunk()

assert(required_modules.sys, "main.lua should require sys")
assert(required_modules.config, "main.lua should require config")
assert(required_modules.application, "main.lua should require application")
assert(app_start_calls == 1, "main.lua should start application once")
assert(run_called, "main.lua should call sys.run")
assert(#task_queue == 0, "main.lua should not register sensor demo loops directly")

print("main_test.lua: PASS")
