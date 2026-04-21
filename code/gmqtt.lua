local gmqtt = {}

local sys = require("sys")
local config = require("config")
local iot = require("iot")

local app_config = nil
local app_state = nil
local mqtt_ready = false

local function safe_json_encode(value)
	if json and type(json.encode) == "function" then
		local ok, encoded = pcall(json.encode, value)
		if ok then
			return encoded
		end
	end

	return tostring(value)
end

local function parse_msg(payload)
	if type(payload) ~= "string" or payload == "" then
		return nil
	end

	local ok, data = pcall(json.decode, payload)
	if not ok then
		return nil
	end

	return data
end

local function to_message_id(msg)
	if type(msg) ~= "table" then
		return ""
	end
	if type(msg.messageId) == "string" and msg.messageId ~= "" then
		return msg.messageId
	end
	if type(msg.id) == "string" and msg.id ~= "" then
		return msg.id
	end
	return ""
end

local function current_config()
	if app_config and type(app_config.get) == "function" then
		return app_config.get()
	end

	return {}
end

local function current_latest()
	if app_state and type(app_state.get_latest) == "function" then
		return app_state.get_latest()
	end

	return nil
end

local function build_get_reply_dp(keys)
	local reply = {}
	local cfg = current_config()
	local latest = current_latest()

	if type(keys) ~= "table" then
		return reply
	end

	for i = 1, #keys do
		local key = keys[i]
		if key == "latest" then
			reply.latest = latest
		elseif cfg[key] ~= nil then
			reply[key] = cfg[key]
		end
	end

	return reply
end

local function apply_set_dp(dp)
	if not app_config or type(app_config.update) ~= "function" then
		return {}
	end

	return app_config.update(dp)
end

local function register_mqtt_receive_handler()
	sys.subscribe(iot.event_recv_name(), function(topic, payload, metas)
		log.info("gmqtt", "收到云端消息", topic, payload, safe_json_encode(metas))

		local msg = parse_msg(payload)
		if not msg then
			log.error("gmqtt", "云端消息解析失败", topic)
			return
		end

		if topic == config.MQTT.getTopic then
			local message_id = to_message_id(msg)
			local reply_dp = build_get_reply_dp(msg.dp)
			local ok = iot.publish_get_reply(message_id, true, reply_dp, nil, nil, msg.deviceId)
			log.info("gmqtt", "已回复配置读取", ok, message_id, safe_json_encode(reply_dp))
		elseif topic == config.MQTT.setTopic then
			local message_id = to_message_id(msg)
			local changed = apply_set_dp(msg.dp)
			local ok = iot.publish_set_reply(message_id, true, changed)
			log.info("gmqtt", "已回复配置写入", ok, message_id, safe_json_encode(changed))
		end
	end)
end

local function register_mqtt_state_handlers()
	sys.subscribe(iot.event_conn_name(), function()
		mqtt_ready = true
		log.info("gmqtt", "MQTT连接成功，允许数据上报")
	end)

	sys.subscribe(iot.event_disc_name(), function(code)
		mqtt_ready = false
		log.info("gmqtt", "MQTT连接断开", code)
	end)
end

local function start_mqtt_connection_task()
	sys.taskInit(function()
		local ip_ready = sys.waitUntil("IP_READY", 30000)
		if not ip_ready then
			log.error("gmqtt", "网络连接超时")
			return
		end

		log.info("gmqtt", "网络连接成功")

		local init_ok = iot.init(config.MQTT)
		if init_ok then
			iot.connect()
		else
			log.error("gmqtt", "iot.init failed")
		end
	end)
end

function gmqtt.publish_snapshot(snapshot)
	if type(snapshot) ~= "table" then
		if log and log.error then
			log.error("gmqtt", "采集快照必须为table")
		end
		return false
	end

	if not mqtt_ready then
		log.info("gmqtt", "MQTT未就绪，跳过本轮上报")
		return false
	end

	log.info("gmqtt", "准备上报采集快照", safe_json_encode(snapshot))
	if iot.publish_dp(snapshot) then
		log.info("gmqtt", "采集快照上报请求已提交")
		return true
	end

	log.error("gmqtt", "采集快照上报失败")
	return false
end

function gmqtt.start(services)
	if type(services) ~= "table" then
		if log and log.error then
			log.error("gmqtt", "services must be table")
		end
		return false
	end

	app_config = services.app_config
	app_state = services.app_state
	mqtt_ready = false

	start_mqtt_connection_task()
	register_mqtt_receive_handler()
	register_mqtt_state_handlers()
	return true
end

return gmqtt
