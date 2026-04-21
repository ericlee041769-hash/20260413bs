local required_modules = {}
local task_queue = {}
local subscriptions = {}
local saved_latest = nil
local published_snapshots = {}
local sms_calls = {}
local alarm_calls = {}
local algorithm_calls = {}
local gmqtt_services = nil
local fskv_init_calls = 0
local sms_ready = false
local collect_calls = 0
local wait_calls = {}
local door_state = true
local wakeup_calls = {}
local pm_sleep_calls = 0
local info_logs = {}
local error_logs = {}

local fake_pm = {}

local fake_sys = {
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	subscribe = function(event_name, handler)
		subscriptions[event_name] = handler
	end,
	wait = function(ms)
		wait_calls[#wait_calls + 1] = ms
		if ms == 10000 then
			error("stop-loop")
		end
	end
}

local fake_fskv = {
	init = function()
		fskv_init_calls = fskv_init_calls + 1
		return true
	end
}

local function current_cfg()
	return {
		usb_interval_ms = 10000,
		battery_interval_ms = 60000,
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

local fake_app_config = {
	load = function()
		assert(fskv_init_calls == 1, "application should init fskv before config load")
		return current_cfg()
	end,
	get = function()
		return current_cfg()
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
		collect_calls = collect_calls + 1
		return {
			timestamp = "2026-04-21 16:00:00",
			current_sensor_mv = 53000,
			door_open = collect_calls > 1,
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

local fake_app_algorithm = {
	apply = function(snapshot, runtime)
		algorithm_calls[#algorithm_calls + 1] = {
			snapshot = snapshot,
			runtime = runtime
		}

		local processed = {
			timestamp = snapshot.timestamp,
			current_sensor_mv = snapshot.current_sensor_mv - 3000,
			door_open = snapshot.door_open,
			temp_hum = {
				[0] = { ok = true, temperature = 66.2 },
				[1] = { ok = true, temperature = 60.0 }
			},
			pressure = snapshot.pressure
		}

		return processed, {
			current = {
				window = { 51000, 52000, 53000 }
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

		if snapshot.door_open then
			local already_active = runtime and runtime.active_map and runtime.active_map.door_open_timeout == true
			return {
				active_map = {
					door_open_timeout = true
				},
				new_alarm_keys = already_active and {} or { "door_open_timeout" },
				should_send_sms = not already_active,
				err_text = "门持续打开超时",
				sms_text = "告警:门持续打开超时; 时间=2026-04-21 16:00:00",
				runtime = {
					active_map = {
						door_open_timeout = true
					},
					door_open_since_ms = 1000
				}
			}
		end

		return {
			active_map = {},
			new_alarm_keys = {},
			should_send_sms = false,
			err_text = "正常",
			sms_text = "",
			runtime = {
				active_map = {},
				door_open_since_ms = nil
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

local fake_app_power = {
	current_profile = function(cfg)
		return {
			mode = "USB",
			interval_ms = cfg.usb_interval_ms,
			prewake_ms = 0
		}
	end,
	should_sleep_after_cycle = function()
		return false
	end,
	prepare_next_wakeup = function(cfg)
		wakeup_calls[#wakeup_calls + 1] = cfg.battery_interval_ms - cfg.battery_prewake_ms
		return true
	end,
	enter_sleep = function()
		pm_sleep_calls = pm_sleep_calls + 1
		return true
	end
}

local fake_ggpio = {
	init = function()
		return true
	end,
	get_door_state = function()
		return door_state
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
	app_algorithm = fake_app_algorithm,
	app_alarm = fake_app_alarm,
	app_sms = fake_app_sms,
	app_power = fake_app_power,
	ggpio = fake_ggpio,
	gsht30 = fake_gsht30,
	gbaro = fake_gbaro,
	glbs = fake_glbs,
	gmqtt = fake_gmqtt
}

local env = {
	_G = nil,
	sys = fake_sys,
	pm = fake_pm,
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
		error = function(...)
			error_logs[#error_logs + 1] = { ... }
		end,
		info = function(...)
			info_logs[#info_logs + 1] = { ... }
		end
	}
}

env._G = env
setmetatable(env, { __index = _G })

local loader, load_err = loadfile("application.lua", "t", env)
assert(loader, load_err)
local application = loader()

assert(application.start(), "application should start")
assert(required_modules.app_algorithm, "application should require app_algorithm")
assert(required_modules.app_alarm, "application should require app_alarm")
assert(required_modules.app_sms, "application should require app_sms")
assert(required_modules.app_power, "application should require app_power")
assert(fskv_init_calls == 1, "application should init fskv once")
assert(gmqtt_services.app_config == fake_app_config, "gmqtt should receive app_config service")
assert(gmqtt_services.app_state == fake_app_state, "gmqtt should receive app_state service")
assert(info_logs[3][2] == "AirLBS init config", "application should log airlbs init config summary")
assert(info_logs[3][3] == "", "application should log blank airlbs project id when config is blank")
assert(info_logs[4][2] == "AirLBS未配置，定位将使用默认值", "application should log when airlbs is skipped")
assert(#task_queue == 1, "application should create one collection task")
assert(type(subscriptions["IP_READY"]) == "function", "application should subscribe IP_READY for sms readiness")
assert(type(subscriptions["APP_DOOR_EDGE"]) == "function", "application should subscribe door edge events")

subscriptions["IP_READY"]()

local ok, err = pcall(task_queue[1])
assert(not ok, "collection loop should be interrupted by fake wait")
assert(string.find(err, "stop-loop", 1, true), "collection loop should stop via fake wait")

assert(saved_latest ~= nil, "latest snapshot should be saved")
assert(saved_latest.timestamp == "2026-04-21 16:00:00", "saved latest snapshot should use collected data")
assert(saved_latest.temp_hum[0].temperature == 66.2, "saved latest snapshot should use processed temperature")
assert(saved_latest.current_sensor_mv == 50000, "saved latest snapshot should use processed current")
assert(saved_latest.err == "正常", "periodic latest snapshot should include normal err text")
assert(#algorithm_calls == 1, "application should apply algorithm once in periodic flow")
assert(#alarm_calls == 1, "application should evaluate alarms once")
assert(#sms_calls == 0, "periodic flow should not send sms without new alarm")
assert(#published_snapshots == 1, "periodic flow should publish once")
assert(published_snapshots[1].temp_hum[0].temperature == 66.2, "published snapshot should use processed temperature")
assert(published_snapshots[1].err == "正常", "periodic published snapshot should include normal err text")

subscriptions["APP_DOOR_EDGE"](101, 1)
assert(#task_queue == 2, "door edge should create one debounce task")

local event_ok, event_err = pcall(task_queue[2])
assert(event_ok, event_err)
assert(#wait_calls >= 3, "application should wait for debounce and timeout confirmation")
assert(wait_calls[2] == 200, "application should debounce door event")
assert(wait_calls[3] == 5000, "application should wait full door timeout before immediate handling")
assert(#algorithm_calls == 2, "door timeout flow should re-run algorithm on immediate cycle")
assert(#alarm_calls == 2, "door timeout flow should evaluate alarms again")
assert(#sms_calls == 1, "door timeout should trigger immediate sms once")
assert(sms_calls[1].phone == "15025376653", "door timeout sms should use configured phone")
assert(#published_snapshots == 2, "door timeout should trigger immediate upload")
assert(published_snapshots[2].err == "门持续打开超时", "door timeout upload should include alarm err text")
assert(wait_calls[1] == 10000, "usb mode should wait the usb sample interval")
assert(pm_sleep_calls == 0, "usb mode should not sleep")

print("application_test.lua: PASS")
