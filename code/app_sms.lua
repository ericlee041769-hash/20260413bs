local app_sms = {}
local sms_ready = false

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

function app_sms.set_ready(ready)
	sms_ready = ready and true or false
	log_info("app_sms", sms_ready and "短信发送已就绪" or "短信发送未就绪")
	return sms_ready
end

function app_sms.is_ready()
	return sms_ready
end

function app_sms.send_alert(phone, text)
	local action

	if not sms_ready then
		log_info("app_sms", "短信模块未就绪，跳过本轮短信发送")
		return false
	end

	if type(phone) ~= "string" or phone == "" then
		log_error("app_sms", "短信号码无效")
		return false
	end

	if type(text) ~= "string" or text == "" then
		log_error("app_sms", "短信内容为空")
		return false
	end

	if not sms or type(sms.sendLong) ~= "function" then
		log_error("app_sms", "sms.sendLong不可用")
		return false
	end

	log_info("app_sms", "准备发送短信", phone, text)
	action = sms.sendLong(phone, text, true)
	if type(action) ~= "table" or type(action.wait) ~= "function" then
		log_error("app_sms", "短信发送句柄无效")
		return false
	end

	if action.wait() then
		log_info("app_sms", "短信发送成功", phone)
		return true
	end

	log_error("app_sms", "短信发送失败", phone)
	return false
end

return app_sms
