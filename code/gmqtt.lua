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

local function extract_temp_humidity(snapshot, index)
	local entry = snapshot and snapshot.temp_hum and snapshot.temp_hum[index]
	if type(entry) ~= "table" or entry.ok ~= true then
		return nil, nil
	end

	return entry.temperature, entry.humidity
end

local function format_location(location)
	local lat = 0
	local lng = 0

	if type(location) == "table" then
		lat = location[1] or 0
		lng = location[2] or 0
	end

	return tostring(lat) .. "," .. tostring(lng)
end

local function round_one_decimal(value)
	if type(value) ~= "number" then
		return value
	end

	if value >= 0 then
		return math.floor(value * 10 + 0.5) / 10
	end

	return math.ceil(value * 10 - 0.5) / 10
end

local function build_gateway_dp(cfg, snapshot)
	local temp1
	local humidity1
	local temp2
	local humidity2
	local reply = {}

	temp1, humidity1 = extract_temp_humidity(snapshot, 0)
	temp2, humidity2 = extract_temp_humidity(snapshot, 1)

	reply.temp = temp1
	reply.door = snapshot and not snapshot.door_open or false
	reply.humidity = humidity1
	reply.err = snapshot and snapshot.err and true or false
	reply.time = snapshot and snapshot.timestamp or ""
	reply.phonenum = cfg and cfg.alarm_sms_phone or ""
	reply.temp2 = temp2
	reply.humidity2 = humidity2
	reply.lpoint = format_location(snapshot and snapshot.location)

	if type(temp1) == "number" and type(temp2) == "number" then
		reply.tempdiff = round_one_decimal(math.abs(temp2 - temp1))
	end

	return reply
end

local function build_get_reply_dp(keys)
	local reply = {}
	local gateway_dp = build_gateway_dp(current_config(), current_latest())

	if type(keys) ~= "table" then
		return reply
	end

	for i = 1, #keys do
		local key = keys[i]
		if gateway_dp[key] ~= nil then
			reply[key] = gateway_dp[key]
		end
	end

	return reply
end

local function apply_set_dp(dp)
	if not app_config or type(app_config.update) ~= "function" then
		return {}
	end

	if type(dp) ~= "table" then
		return {}
	end

	local applied = app_config.update({
		alarm_sms_phone = dp.phonenum
	})

	if type(applied.alarm_sms_phone) == "string" then
		return {
			phonenum = applied.alarm_sms_phone
		}
	end

	return {}
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

	local gateway_dp = build_gateway_dp(current_config(), snapshot)

	log.info("gmqtt", "准备上报采集快照", safe_json_encode(gateway_dp))
	if iot.publish_dp(gateway_dp) then
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
