local app_sms = {}

local function log_error(...)
	if log and type(log.error) == "function" then
		log.error(...)
	end
end

function app_sms.send_alert(phone, text)
	local action

	if type(phone) ~= "string" or phone == "" then
		log_error("app_sms", "invalid phone")
		return false
	end

	if type(text) ~= "string" or text == "" then
		log_error("app_sms", "invalid text")
		return false
	end

	if not sms or type(sms.sendLong) ~= "function" then
		log_error("app_sms", "sms.sendLong unavailable")
		return false
	end

	action = sms.sendLong(phone, text, true)
	if type(action) ~= "table" or type(action.wait) ~= "function" then
		log_error("app_sms", "invalid sendLong action")
		return false
	end

	if action.wait() then
		return true
	end

	log_error("app_sms", "send failed", phone)
	return false
end

return app_sms
