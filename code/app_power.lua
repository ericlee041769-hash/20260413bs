local app_power = {}

local ggpio = require("ggpio")
local BATTERY_PREWAKE_MS = 5000

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

function app_power.current_mode(cfg)
	local usb_present = ggpio.get_usb_power_state()

	if usb_present == nil then
		log_error("app_power", "VBUS检测失败，回退到USB模式")
		return "USB"
	end

	if usb_present then
		return "USB"
	end

	return "BATTERY"
end

function app_power.current_profile(cfg)
	local mode = app_power.current_mode(cfg)

	if mode == "BATTERY" then
		return {
			mode = "BATTERY",
			interval_ms = cfg.battery_interval_ms,
			prewake_ms = BATTERY_PREWAKE_MS
		}
	end

	return {
		mode = "USB",
		interval_ms = cfg.usb_interval_ms,
		prewake_ms = 0
	}
end

function app_power.should_sleep_after_cycle(cfg)
	return app_power.current_mode(cfg) == "BATTERY"
end

function app_power.next_wakeup_delay_ms(cfg)
	local delay_ms = cfg.battery_interval_ms - BATTERY_PREWAKE_MS

	if delay_ms < 0 then
		return 0
	end

	return delay_ms
end

function app_power.prepare_next_wakeup(cfg)
	local delay_ms = app_power.next_wakeup_delay_ms(cfg)

	if not pm or type(pm.dtimerStart) ~= "function" then
		log_error("app_power", "定时唤醒接口不可用，跳过休眠")
		return false
	end

	if pm.dtimerStart(delay_ms) == false then
		log_error("app_power", "定时唤醒配置失败", delay_ms)
		return false
	end

	log_info("app_power", "已配置电池模式定时唤醒", delay_ms)
	return true
end

function app_power.enter_sleep()
	if not pm or type(pm.force) ~= "function" then
		log_error("app_power", "低功耗接口不可用，跳过休眠")
		return false
	end

	if pm.force(pm.LIGHT) == false then
		log_error("app_power", "进入低功耗失败")
		return false
	end

	log_info("app_power", "已进入低功耗")
	return true
end

return app_power
