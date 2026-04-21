local application = {}

local app_config = require("app_config")
local app_state = require("app_state")
local app_collect = require("app_collect")
local app_alarm = require("app_alarm")
local app_sms = require("app_sms")
local ggpio = require("ggpio")
local gsht30 = require("gsht30")
local gbaro = require("gbaro")
local glbs = require("glbs")
local gmqtt = require("gmqtt")

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

	if type(cfg.airlbs_project_id) == "string" and cfg.airlbs_project_id ~= "" then
		if not glbs.init({
			project_id = cfg.airlbs_project_id,
			project_key = cfg.airlbs_project_key,
			timeout = cfg.airlbs_timeout
		}) then
			log_error("application", "AirLBS初始化失败")
			return false
		end
		log_info("application", "AirLBS初始化成功")
	else
		log_info("application", "AirLBS未配置，定位将使用默认值")
	end

	return true
end

local function start_collection_loop()
	sys.taskInit(function()
		local last_report_ms = 0
		local alarm_runtime = {
			active_map = {},
			door_open_since_ms = nil
		}

		while true do
			local cfg = app_config.get()
			log_info("application", "开始一轮业务采集")
			local snapshot = app_collect.collect_once()
			local alarm = app_alarm.evaluate(cfg, snapshot, alarm_runtime, now_ms())
			snapshot.err = next(alarm.active_map) ~= nil

			log_info("application", "本轮采集快照", safe_json_encode(snapshot))
			app_state.save_latest(snapshot)
			alarm_runtime = type(alarm.runtime) == "table" and alarm.runtime or alarm_runtime

			if alarm.should_send_sms == true then
				app_sms.send_alert(cfg.alarm_sms_phone, alarm.sms_text)
			end

			if last_report_ms == 0 or (now_ms() - last_report_ms) >= cfg.report_interval_ms then
				gmqtt.publish_snapshot(snapshot)
				last_report_ms = now_ms()
			end

			sys.wait(cfg.sample_interval_ms)
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
