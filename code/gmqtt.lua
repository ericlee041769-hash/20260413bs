local gmqtt = {}

local sys = require("sys")
local config = require("config")
local iot = require("iot")

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

local function build_get_reply_dp(device_props, keys)
	local reply = {}
	if type(keys) ~= "table" then
		return reply
	end
	for i = 1, #keys do
		local key = keys[i]
		if type(key) == "string" and device_props[key] ~= nil then
			reply[key] = device_props[key]
		end
	end
	return reply
end

local function apply_set_dp(device_props, dp)
	if type(dp) ~= "table" then
		return {}
	end
	for k, v in pairs(dp) do
		device_props[k] = v
	end
	return dp
end

local function register_mqtt_receive_handler(device_props)
	sys.subscribe(iot.event_recv_name(), function(topic, payload, metas)
		log.info("gmqtt", "mqtt recv", topic, payload, json.encode(metas))

		local msg = parse_msg(payload)
		if not msg then
			return
		end

		if topic == config.MQTT.getTopic then
			local message_id = to_message_id(msg)
			local req = msg.dp
			local reply_dp = build_get_reply_dp(device_props, req)
			local ok = iot.publish_get_reply(message_id, true, reply_dp, nil, nil, msg.deviceId)
			log.info("gmqtt", "dp/get reply", ok, message_id, json.encode(reply_dp))
		elseif topic == config.MQTT.setTopic then
			local message_id = to_message_id(msg)
			local changed = apply_set_dp(device_props, msg.dp)
			local ok = iot.publish_set_reply(message_id, true, changed)
			log.info("gmqtt", "dp/set reply", ok, message_id, json.encode(changed))
		end
	end)
end

local function register_mqtt_state_handlers()
	sys.subscribe(iot.event_conn_name(), function()
		log.info("gmqtt", "mqtt connected event")
	end)

	sys.subscribe(iot.event_disc_name(), function(code)
		log.info("gmqtt", "mqtt disconnected", code)
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

local function start_dp_publish_task(device_props)
	sys.taskInit(function()
		math.randomseed(os.time())
		math.random()
		math.random()

		while true do
			if iot.ready() then
				local temp = math.random(150, 350) / 10
				local fanSpeed = math.random(5, 50) / 10
				local door = math.random(0, 1) == 1
				local humidity = math.random(300, 900) / 10
				local err = math.random(1, 20) == 1
				local now = os.date("%Y-%m-%d %H:%M:%S")

				device_props.temp = temp
				device_props.fanSpeed = fanSpeed
				device_props.door = door
				device_props.humidity = humidity
				device_props.err = err
				device_props.time = now

				local ok = iot.publish_dp(temp, fanSpeed, door, humidity, err, now)
				log.info("gmqtt", "publish_dp result", ok, temp, fanSpeed, door, humidity, err, now)
			end
			sys.wait(10000)
		end
	end)
end

function gmqtt.start(device_props)
	if type(device_props) ~= "table" then
		if log and log.error then
			log.error("gmqtt", "device_props must be table")
		end
		return false
	end

	start_mqtt_connection_task()
	register_mqtt_receive_handler(device_props)
	register_mqtt_state_handlers()
	start_dp_publish_task(device_props)
	return true
end

return gmqtt
