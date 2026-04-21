local required_modules = {}
local task_queue = {}
local subscriptions = {}
local wait_calls = {}
local wakeup_calls = {}
local sleep_calls = 0
local published_snapshots = {}

local fake_sys = {
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	subscribe = function(event_name, handler)
		subscriptions[event_name] = handler
	end,
	wait = function(ms)
		wait_calls[#wait_calls + 1] = ms
		if ms == 5000 then
			error("stop-loop")
		end
	end
}

local fake_fskv = {
	init = function()
		return true
	end
}

local function current_cfg()
	return {
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
	}
end

local fake_modules = {
	app_config = {
		load = function()
			return current_cfg()
		end,
		get = function()
			return current_cfg()
		end
	},
	app_state = {
		save_latest = function(snapshot)
			return snapshot
		end
	},
	app_collect = {
		collect_once = function()
			return {
				timestamp = "2026-04-21 18:00:00",
				current_sensor_mv = 30000,
				door_open = false,
				temp_hum = {
					[0] = { ok = true, temperature = 25.0, humidity = 50.0 },
					[1] = { ok = true, temperature = 26.0, humidity = 51.0 }
				},
				pressure = {
					[1] = { ok = true, pressure = 100.0 },
					[2] = { ok = true, pressure = 101.2 }
				}
			}
		end
	},
	app_algorithm = {
		apply = function(snapshot)
			return snapshot, {}
		end
	},
	app_alarm = {
		evaluate = function(cfg, snapshot, runtime, now_ms)
			return {
				active_map = {},
				new_alarm_keys = {},
				should_send_sms = false,
				sms_text = "",
				runtime = runtime or {
					active_map = {},
					door_open_since_ms = nil
				}
			}
		end
	},
	app_power = {
		current_profile = function(cfg)
			return {
				mode = "BATTERY",
				sample_interval_ms = cfg.battery_sample_interval_ms,
				report_interval_ms = cfg.battery_report_interval_ms,
				prewake_ms = cfg.battery_prewake_ms
			}
		end,
		should_sleep_after_cycle = function()
			return true
		end,
		prepare_next_wakeup = function(cfg)
			wakeup_calls[#wakeup_calls + 1] = cfg.battery_sample_interval_ms - cfg.battery_prewake_ms
			return true
		end,
		enter_sleep = function()
			sleep_calls = sleep_calls + 1
			return true
		end
	},
	app_sms = {
		set_ready = function() end,
		send_alert = function()
			return true
		end
	},
	ggpio = {
		init = function()
			return true
		end,
		get_door_state = function()
			return false
		end
	},
	gsht30 = {
		init = function()
			return true
		end
	},
	gbaro = {
		init = function()
			return true
		end
	},
	glbs = {
		init = function()
			return true
		end
	},
	gmqtt = {
		start = function()
			return true
		end,
		publish_snapshot = function(snapshot)
			published_snapshots[#published_snapshots + 1] = snapshot
			return true
		end
	}
}

local env = {
	_G = nil,
	sys = fake_sys,
	fskv = fake_fskv,
	pm = {},
	os = {
		time = function()
			return 100
		end
	},
	require = function(name)
		required_modules[name] = true
		local mod = fake_modules[name]
		assert(mod, "unexpected require: " .. tostring(name))
		return mod
	end,
	log = {
		error = function() end,
		info = function() end
	}
}

env._G = env
setmetatable(env, { __index = _G })

local loader, load_err = loadfile("application.lua", "t", env)
assert(loader, load_err)
local application = loader()

assert(application.start(), "application should start in battery mode scenario")
assert(type(subscriptions["IP_READY"]) == "function", "application should still subscribe IP_READY")
assert(#task_queue == 1, "battery mode scenario should create one collection task")

local ok, err = pcall(task_queue[1])
assert(not ok, "battery mode loop should stop via fake wait")
assert(string.find(err, "stop-loop", 1, true), "battery mode loop should stop via prewake wait")
assert(#published_snapshots == 1, "battery mode cycle should still publish snapshot")
assert(#wakeup_calls == 1, "battery mode should configure one wakeup")
assert(wakeup_calls[1] == 55000, "battery mode should schedule interval minus prewake")
assert(sleep_calls == 1, "battery mode should enter sleep after cycle")
assert(wait_calls[1] == 5000, "battery mode should use prewake wait after sleep scheduling")

print("application_power_mode_test.lua: PASS")
