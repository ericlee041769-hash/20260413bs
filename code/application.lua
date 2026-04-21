local application = {}

local app_config = require("app_config")
local app_state = require("app_state")
local app_collect = require("app_collect")
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

		while true do
			local cfg = app_config.get()
			local snapshot = app_collect.collect_once()

			app_state.save_latest(snapshot)

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
