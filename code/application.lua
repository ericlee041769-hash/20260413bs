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

local function now_ms()
	return (os.time() or 0) * 1000
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
		glbs.init({
			project_id = cfg.airlbs_project_id,
			project_key = cfg.airlbs_project_key,
			timeout = cfg.airlbs_timeout
		})
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
			local snapshot = app_collect.collect_once()
			local alarm = app_alarm.evaluate(cfg, snapshot, alarm_runtime, now_ms())

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
	local cfg = app_config.load()

	if not init_modules(cfg) then
		if log and log.error then
			log.error("application", "module init failed")
		end
		return false
	end

	gmqtt.start({
		app_config = app_config,
		app_state = app_state
	})
	start_collection_loop()
	return true
end

return application
