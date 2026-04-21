local required_modules = {}
local task_queue = {}
local subscriptions = {}
local saved_latest = nil
local published_snapshots = {}
local sms_calls = {}
local alarm_calls = {}
local gmqtt_services = nil
local fskv_init_calls = 0
local sms_ready = false

local fake_sys = {
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	subscribe = function(event_name, handler)
		subscriptions[event_name] = handler
	end,
	wait = function()
		error("stop-loop")
	end
}

local fake_fskv = {
	init = function()
		fskv_init_calls = fskv_init_calls + 1
		return true
	end
}

local fake_app_config = {
	load = function()
		assert(fskv_init_calls == 1, "application should init fskv before config load")
		return {
			sample_interval_ms = 10000,
			report_interval_ms = 10000,
			airlbs_project_id = "",
			airlbs_project_key = "",
			airlbs_timeout = 10000,
			alarm_sms_phone = "15025376653"
		}
	end,
	get = function()
		return {
			sample_interval_ms = 10000,
			report_interval_ms = 10000,
			airlbs_project_id = "",
			airlbs_project_key = "",
			airlbs_timeout = 10000,
			alarm_sms_phone = "15025376653"
		}
	end
}

local fake_app_state = {
	save_latest = function(snapshot)
		saved_latest = snapshot
		return snapshot
	end
}

local fake_app_collect = {
	collect_once = function()
		return {
			timestamp = "2026-04-21 16:00:00",
			current_sensor_mv = 53000,
			door_open = true,
			temp_hum = {
				[0] = { ok = true, temperature = 86.2 },
				[1] = { ok = true, temperature = 80.0 }
			},
			pressure = {
				[1] = { ok = true, pressure = 100.0 },
				[2] = { ok = true, pressure = 100.7 }
			}
		}
	end
}

local fake_app_alarm = {
	evaluate = function(cfg, snapshot, runtime, now_ms)
		alarm_calls[#alarm_calls + 1] = {
			cfg = cfg,
			snapshot = snapshot,
			runtime = runtime,
			now_ms = now_ms
		}
		return {
			active_map = {
				temp1_high = true
			},
			new_alarm_keys = {
				"temp1_high"
			},
			should_send_sms = true,
			sms_text = "告警:温度1高温=86.2; 时间=2026-04-21 16:00:00",
			runtime = {
				active_map = {
					temp1_high = true
				},
				door_open_since_ms = 1000
			}
		}
	end
}

local fake_app_sms = {
	set_ready = function(ready)
		sms_ready = ready and true or false
	end,
	send_alert = function(phone, text)
		if not sms_ready then
			return false
		end
		sms_calls[#sms_calls + 1] = {
			phone = phone,
			text = text
		}
		return false
	end
}

local fake_ggpio = {
	init = function()
		return true
	end
}

local fake_gsht30 = {
	init = function()
		return true
	end
}

local fake_gbaro = {
	init = function()
		return true
	end
}

local fake_glbs = {
	init = function()
		return true
	end
}

local fake_gmqtt = {
	start = function(services)
		gmqtt_services = services
		return true
	end,
	publish_snapshot = function(snapshot)
		published_snapshots[#published_snapshots + 1] = snapshot
		return true
	end
}

local fake_modules = {
	app_config = fake_app_config,
	app_state = fake_app_state,
	app_collect = fake_app_collect,
	app_alarm = fake_app_alarm,
	app_sms = fake_app_sms,
	ggpio = fake_ggpio,
	gsht30 = fake_gsht30,
	gbaro = fake_gbaro,
	glbs = fake_glbs,
	gmqtt = fake_gmqtt
}

local env = {
	_G = nil,
	sys = fake_sys,
	fskv = fake_fskv,
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

assert(application.start(), "application should start")
assert(required_modules.app_alarm, "application should require app_alarm")
assert(required_modules.app_sms, "application should require app_sms")
assert(fskv_init_calls == 1, "application should init fskv once")
assert(gmqtt_services.app_config == fake_app_config, "gmqtt should receive app_config service")
assert(gmqtt_services.app_state == fake_app_state, "gmqtt should receive app_state service")
assert(#task_queue == 1, "application should create one collection task")
assert(type(subscriptions["IP_READY"]) == "function", "application should subscribe IP_READY for sms readiness")

subscriptions["IP_READY"]()

local ok, err = pcall(task_queue[1])
assert(not ok, "collection loop should be interrupted by fake wait")
assert(string.find(err, "stop-loop", 1, true), "collection loop should stop via fake wait")

assert(saved_latest ~= nil, "latest snapshot should be saved")
assert(saved_latest.timestamp == "2026-04-21 16:00:00", "saved latest snapshot should use collected data")
assert(saved_latest.err == true, "saved latest snapshot should include err flag")
assert(#alarm_calls == 1, "application should evaluate alarms once")
assert(#sms_calls == 1, "application should send sms when a new alarm appears")
assert(sms_calls[1].phone == "15025376653", "sms should use configured phone")
assert(#published_snapshots == 1, "mqtt publish should continue after sms failure")
assert(published_snapshots[1].timestamp == "2026-04-21 16:00:00", "published snapshot should match collected data")
assert(published_snapshots[1].err == true, "published snapshot should include err flag")

print("application_test.lua: PASS")
