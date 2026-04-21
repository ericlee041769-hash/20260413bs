local config = {}

config.MQTT = {
	name = "developLink",
	host = "con-mqttn.developlink.cloud",
	port = 1883,
	clientId = "d864865085015494",
	username = "pe475014317757",
	password = "7c59ffbea4cb450283bbaa34d685c6d5",
	postTopic = "/pe475014317757/d864865085015494/dp/post",
	getTopic = "/pe475014317757/d864865085015494/dp/get",
	setTopic = "/pe475014317757/d864865085015494/dp/set",
	getReplyTopic = "/pe475014317757/d864865085015494/dp/get/reply",
	setReplyTopic = "/pe475014317757/d864865085015494/dp/set/reply"
}

config.RUNTIME_DEFAULTS = {
	usb_interval_ms = 10000,
	battery_interval_ms = 60000,
	battery_prewake_ms = 5000,
	airlbs_project_id = "lvU4QJ",
	airlbs_project_key = "hbHtgCRY8OUvCqEC3NEyLZb5CS0w7oHV",
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

config.RUNTIME_FIELD_TYPES = {
	usb_interval_ms = "number",
	battery_interval_ms = "number",
	battery_prewake_ms = "number",
	airlbs_project_id = "string",
	airlbs_project_key = "string",
	airlbs_timeout = "number",
	temp_low = "number",
	temp_high = "number",
	temp_diff_high = "number",
	current_low = "number",
	current_high = "number",
	pressure_diff_low = "number",
	pressure_diff_high = "number",
	door_open_warn_ms = "number",
	alarm_sms_phone = "string"
}

config.RUNTIME_MUTABLE_FIELDS = {
	usb_interval_ms = true,
	battery_interval_ms = true,
	battery_prewake_ms = true,
	airlbs_project_id = true,
	airlbs_project_key = true,
	airlbs_timeout = true,
	temp_low = true,
	temp_high = true,
	temp_diff_high = true,
	current_low = true,
	current_high = true,
	pressure_diff_low = true,
	pressure_diff_high = true,
	door_open_warn_ms = true,
	alarm_sms_phone = true
}

config.GATEWAY_CONFIG_FIELDS = {
	usb_interval_ms = true,
	battery_interval_ms = true,
	battery_prewake_ms = true,
	temp_low = true,
	temp_high = true,
	temp_diff_high = true,
	current_low = true,
	current_high = true,
	pressure_diff_low = true,
	pressure_diff_high = true,
	door_open_warn_ms = true,
	alarm_sms_phone = true
}

return config
