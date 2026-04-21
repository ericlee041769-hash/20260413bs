local iot = {}

local mqtt_client = nil
local mqtt_cfg = nil
local is_inited = false
local pending_messages = {}

local EVT_RECV = "IOT_MQTT_RECV"
local EVT_CONN = "IOT_MQTT_CONNECTED"
local EVT_DISC = "IOT_MQTT_DISCONNECTED"

local function now_ms()
	return (os.time() or 0) * 1000.0
end

local function gen_message_id()
	local seed = math.random(10000, 99999)
	return tostring(os.time() or 0) .. "000" .. tostring(seed)
end

local function subscribe_topics(client)
	local topics = {}
	if mqtt_cfg and mqtt_cfg.getTopic then
		topics[#topics + 1] = mqtt_cfg.getTopic
	end
	if mqtt_cfg and mqtt_cfg.setTopic then
		topics[#topics + 1] = mqtt_cfg.setTopic
	end

	for i = 1, #topics do
		local topic = topics[i]
		local sub_id = client:subscribe(topic, 1)
		if sub_id then
			log.info("iot.mqtt_cb", "subscribe ok", topic, sub_id)
		else
			log.error("iot.mqtt_cb", "subscribe failed", topic)
		end
	end
end

local function mqtt_cb(client, event, data, payload, metas)
	log.info("iot.mqtt_cb", event, data, payload)

	if event == "conack" then
		log.info("iot.mqtt_cb", "mqtt connected")
		subscribe_topics(client)
		sys.publish(EVT_CONN)
	elseif event == "sent" then
		local pending = pending_messages[data]
		if pending then
			log.info("iot.mqtt_cb", "sent", data, pending.topic)
			pending_messages[data] = nil
		else
			log.info("iot.mqtt_cb", "sent", data, "")
		end
	elseif event == "recv" then
		-- 统一通过系统消息总线向外透传收到的主题和消息体
		sys.publish(EVT_RECV, data, payload, metas)
	elseif event == "disconnect" then
		sys.publish(EVT_DISC, data)
	elseif event == "error" then
		log.error("iot.mqtt_cb", "error", data, payload)
	end
end

function iot.init(cfg)
	if not cfg then
		log.error("iot.init", "cfg is nil")
		return false
	end

	mqtt_cfg = cfg

	if mqtt_client then
		mqtt_client:close()
		mqtt_client = nil
	end

	mqtt_client = mqtt.create(nil, mqtt_cfg.host, mqtt_cfg.port, false, false)
	if not mqtt_client then
		log.error("iot.init", "mqtt.create failed")
		return false
	end

	mqtt_client:debug(false)

	local auth_ok = mqtt_client:auth(mqtt_cfg.clientId, mqtt_cfg.username, mqtt_cfg.password, true)
	if not auth_ok then
		log.error("iot.init", "mqtt auth failed")
		mqtt_client:close()
		mqtt_client = nil
		return false
	end

	mqtt_client:on(mqtt_cb)
	is_inited = true
	log.info("iot.init", "ok")
	return true
end

function iot.connect()
	if not is_inited or not mqtt_client then
		log.error("iot.connect", "mqtt not inited")
		return false
	end

	local ok = mqtt_client:connect()
	if ok then
		log.info("iot.connect", "connect request ok")
	else
		log.error("iot.connect", "connect request failed")
	end
	return ok and true or false
end

function iot.disconnect()
	if not mqtt_client then
		return false
	end
	return mqtt_client:disconnect() and true or false
end

function iot.close()
	if mqtt_client then
		mqtt_client:close()
		mqtt_client = nil
	end
	is_inited = false
end

function iot.ready()
	if not mqtt_client then
		return false
	end
	return mqtt_client:ready()
end

function iot.publish(topic, data, qos, retain)
	local msg_id

	if not mqtt_client or not mqtt_client:ready() then
		log.error("iot.publish", "mqtt not ready")
		return nil
	end
	log.info("iot.publish", topic, data)
	msg_id = mqtt_client:publish(topic, data, qos or 0, retain or 0)
	if msg_id then
		pending_messages[msg_id] = {
			topic = topic
		}
		log.info("iot.publish", "queued", topic, msg_id)
	else
		log.error("iot.publish", "publish failed", topic)
	end
	return msg_id
end

-- 按平台指定格式上报DP数据。
-- 兼容两种调用方式：
-- 1. 旧版演示调用：iot.publish_dp(temp, fanSpeed, door, humidity, err, time)
-- 2. 新版应用调用：iot.publish_dp(dp_table)
function iot.publish_dp(temp, fanSpeed, door, humidity, err, time)
	local dp

	if not mqtt_cfg or not mqtt_cfg.postTopic then
		log.error("iot.publish_dp", "postTopic not configured")
		return false
	end

	if type(temp) == "table" and fanSpeed == nil then
		dp = temp
	else
		if type(temp) ~= "number" then
			log.error("iot.publish_dp", "temp must be number")
			return false
		end
		if type(fanSpeed) ~= "number" then
			log.error("iot.publish_dp", "fanSpeed must be number")
			return false
		end
		if type(door) ~= "boolean" then
			log.error("iot.publish_dp", "door must be boolean")
			return false
		end
		if type(humidity) ~= "number" then
			log.error("iot.publish_dp", "humidity must be number")
			return false
		end
		if type(err) ~= "boolean" then
			log.error("iot.publish_dp", "err must be boolean")
			return false
		end
		if type(time) ~= "string" or time == "" then
			log.error("iot.publish_dp", "time must be non-empty string")
			return false
		end

		dp = {
			temp = temp,
			fanSpeed = fanSpeed,
			door = door,
			humidity = humidity,
			err = err,
			time = time
		}
	end

	local payload = {
		deviceId = mqtt_cfg.clientId,
		dp = dp
	}

	local body = json.encode(payload)
	local msg_id = iot.publish(mqtt_cfg.postTopic, body, 1, 0)
	if msg_id then
		return true
	end
	return false
end

function iot.publish_get_reply(messageId, success, dp, code, message, deviceId)
	if not mqtt_cfg or not mqtt_cfg.getReplyTopic then
		log.error("iot.publish_get_reply", "getReplyTopic not configured")
		return false
	end

	if type(messageId) ~= "string" or messageId == "" then
		messageId = gen_message_id()
	end

	local payload = {
		timestamp = now_ms(),
		messageId = messageId,
		success = success and true or false,
		deviceId = deviceId or mqtt_cfg.clientId
	}

	if success then
		payload.dp = dp or {}
	else
		payload.code = code or "error_code"
		payload.message = message or "failed"
	end

	local body = json.encode(payload)
	local msg_id = iot.publish(mqtt_cfg.getReplyTopic, body, 1, 0)
	return msg_id and true or false
end

function iot.publish_set_reply(messageId, success, dp, code, message)
	if not mqtt_cfg or not mqtt_cfg.setReplyTopic then
		log.error("iot.publish_set_reply", "setReplyTopic not configured")
		return false
	end

	if type(messageId) ~= "string" or messageId == "" then
		messageId = gen_message_id()
	end

	local payload = {
		timestamp = now_ms(),
		messageId = messageId,
		success = success and true or false
	}

	if dp and type(dp) == "table" then
		payload.dp = dp
	end

	if not success then
		payload.code = code or "error_code"
		payload.message = message or "failed"
	end

	local body = json.encode(payload)
	local msg_id = iot.publish(mqtt_cfg.setReplyTopic, body, 1, 0)
	return msg_id and true or false
end

function iot.event_recv_name()
	return EVT_RECV
end

function iot.event_conn_name()
	return EVT_CONN
end

function iot.event_disc_name()
	return EVT_DISC
end

return iot
