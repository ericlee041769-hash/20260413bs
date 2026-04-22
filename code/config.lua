-- 静态配置中心。
-- 这里放的是出厂默认值、字段类型约束，以及云端允许改写的配置白名单。
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
	-- 供电模式切换后的采集周期。
	usb_interval_ms = 10000,
	battery_interval_ms = 60000,
	-- AirLBS 默认参数，空值会导致定位模块不初始化。
	airlbs_project_id = "lvU4QJ",
	airlbs_project_key = "hbHtgCRY8OUvCqEC3NEyLZb5CS0w7oHV",
	airlbs_timeout = 10000,
	-- 告警阈值默认值。
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
	-- app_config.update 会用这里校验云端和本地写入的值类型。
	usb_interval_ms = "number",
	battery_interval_ms = "number",
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
	-- 运行时可变字段，意味着会进入 fskv 持久化并允许本地/云端更新。
	usb_interval_ms = true,
	battery_interval_ms = true,
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
	-- 云端平台允许读写的配置字段子集。
	usb_interval_ms = true,
	battery_interval_ms = true,
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
