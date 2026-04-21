local application = {}

local app_config = require("app_config")
local app_state = require("app_state")
local app_collect = require("app_collect")
local app_algorithm = require("app_algorithm")
local app_alarm = require("app_alarm")
local app_power = require("app_power")
local app_sms = require("app_sms")
local ggpio = require("ggpio")
local gsht30 = require("gsht30")
local gbaro = require("gbaro")
local glbs = require("glbs")
local gmqtt = require("gmqtt")

local DOOR_EDGE_EVENT = "APP_DOOR_EDGE"
local DOOR_DEBOUNCE_MS = 200

local function log_info(...)
	if log and type(log.info) == "function" then
		log.info(...)
	end
end

local function log_error(...)
	if log and type(log.error) == "function" then
		log.error(...)
	end
end

local function safe_json_encode(value)
	if json and type(json.encode) == "function" then
		local ok, encoded = pcall(json.encode, value)
		if ok then
			return encoded
		end
	end

	return tostring(value)
end

local function now_ms()
	return (os.time() or 0) * 1000
end

local function init_storage()
	if not fskv or type(fskv.init) ~= "function" then
		log_info("application", "fskv不可用，跳过存储初始化")
		return true
	end

	if fskv.init() == false then
		log_error("application", "fskv初始化失败")
		return false
	end

	log_info("application", "fskv初始化成功")
	return true
end

local function register_runtime_handlers()
	if type(app_sms.set_ready) == "function" then
		app_sms.set_ready(false)
	end

	if sys and type(sys.subscribe) == "function" then
		sys.subscribe("IP_READY", function()
			log_info("application", "网络已就绪，允许短信发送")
			if type(app_sms.set_ready) == "function" then
				app_sms.set_ready(true)
			end
		end)
	end
end

local function init_modules(cfg)
	local ok = ggpio.init()
	if not ok then
		return false
	end

	if not gsht30.init() then
		return false
	end

	if not gbaro.init() then
		return false
	end

	log_info(
		"application",
		"AirLBS init config",
		type(cfg.airlbs_project_id) == "string" and cfg.airlbs_project_id or "",
		type(cfg.airlbs_project_key) == "string" and #cfg.airlbs_project_key or 0,
		cfg.airlbs_timeout
	)

	if type(cfg.airlbs_project_id) == "string" and cfg.airlbs_project_id ~= "" then
		if not glbs.init({
			project_id = cfg.airlbs_project_id,
			project_key = cfg.airlbs_project_key,
			timeout = cfg.airlbs_timeout
		}) then
			log_error("application", "AirLBS初始化失败")
			return false
		end
		log_info("application", "AirLBS初始化成功", type(glbs.is_ready) == "function" and glbs.is_ready() or nil)
	else
		log_info("application", "AirLBS未配置，定位将使用默认值")
	end

	return true
end

local function start_collection_loop()
	local algo_runtime = nil
	local alarm_runtime = {
		active_map = {},
		door_open_since_ms = nil
	}
	local door_watch_active = false

	local function process_cycle(reason)
		local cfg = app_config.get()
		local profile = app_power.current_profile(cfg)
		local raw_snapshot
		local snapshot
		local alarm

		log_info("application", "开始一轮业务采集", reason, profile.mode)
		raw_snapshot = app_collect.collect_once()
		snapshot, algo_runtime = app_algorithm.apply(raw_snapshot, algo_runtime)
		alarm = app_alarm.evaluate(cfg, snapshot, alarm_runtime, now_ms())
		if type(alarm.err_text) == "string" and alarm.err_text ~= "" then
			snapshot.err = alarm.err_text
		elseif next(alarm.active_map) ~= nil then
			snapshot.err = "告警"
		else
			snapshot.err = "正常"
		end

		log_info("application", "本轮采集快照", safe_json_encode(snapshot))
		app_state.save_latest(snapshot)
		alarm_runtime = type(alarm.runtime) == "table" and alarm.runtime or alarm_runtime

		if alarm.should_send_sms == true then
			app_sms.send_alert(cfg.alarm_sms_phone, alarm.sms_text)
		end

		gmqtt.publish_snapshot(snapshot)

		return snapshot, alarm, profile
	end

	if sys and type(sys.subscribe) == "function" then
		sys.subscribe(DOOR_EDGE_EVENT, function(pin, level)
			log_info("application", "收到门磁边沿事件", pin, level)
			if door_watch_active then
				log_info("application", "门磁超时观察已存在，忽略重复边沿")
				return
			end

			door_watch_active = true
			sys.taskInit(function()
				local cfg = app_config.get()
				local confirmed_open_at

				sys.wait(DOOR_DEBOUNCE_MS)
				if not ggpio.get_door_state() then
					log_info("application", "门磁消抖后状态为关闭，忽略本次事件")
					door_watch_active = false
					return
				end

				log_info("application", "门磁消抖后确认打开，开始超时观察", cfg.door_open_warn_ms)
				confirmed_open_at = now_ms()
				if type(alarm_runtime.door_open_since_ms) ~= "number" then
					alarm_runtime.door_open_since_ms = confirmed_open_at
				end

				sys.wait(cfg.door_open_warn_ms)
				if not ggpio.get_door_state() then
					log_info("application", "超时观察期间门已关闭，取消立即告警")
					door_watch_active = false
					return
				end

				if alarm_runtime.door_open_since_ms > (now_ms() - cfg.door_open_warn_ms) then
					alarm_runtime.door_open_since_ms = now_ms() - cfg.door_open_warn_ms
				end

				log_info("application", "门持续打开超时，立即执行告警与上报")
				process_cycle("door_timeout")
				door_watch_active = false
			end)
		end)
	end

	sys.taskInit(function()
		while true do
			local cfg = app_config.get()
			local profile

			_, _, profile = process_cycle("periodic")
			if app_power.should_sleep_after_cycle(cfg) then
				if app_power.prepare_next_wakeup(cfg) then
					app_power.enter_sleep()
				end
				if profile.prewake_ms > 0 then
					sys.wait(profile.prewake_ms)
				end
			else
				sys.wait(profile.interval_ms)
			end
		end
	end)
end

function application.start()
	log_info("application", "应用启动开始")
	if not init_storage() then
		return false
	end

	register_runtime_handlers()
	local cfg = app_config.load()

	if not init_modules(cfg) then
		log_error("application", "模块初始化失败")
		return false
	end

	gmqtt.start({
		app_config = app_config,
		app_state = app_state
	})
	start_collection_loop()
	log_info("application", "应用启动完成")
	return true
end

return application
