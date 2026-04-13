PROJECT = "Air780EPM"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.config = require("config")
_G.iot = require("iot")
_G.application = require("application")

local device_props = {
	sn = "AIR780EPM-SN-001",
	model = "Air780EPM",
	color = "red",
	temp = 25.0,
	fanSpeed = 1.0,
	door = false,
	humidity = 50.0,
	err = false,
	time = os.date("%Y-%m-%d %H:%M:%S")
}

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

local function build_get_reply_dp(keys)
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

local function apply_set_dp(dp)
	if type(dp) ~= "table" then
		return {}
	end
	for k, v in pairs(dp) do
		device_props[k] = v
	end
	return dp
end

sys.taskInit(function()
	local ip_ready = sys.waitUntil("IP_READY", 30000)
	if not ip_ready then
		log.error("main", "网络连接超时")
		return
	end

	log.info("main", "网络连接成功")

	-- MQTT初始化与连接测试
	local init_ok = iot.init(config.MQTT)
	if init_ok then
		iot.connect()
	else
		log.error("main", "iot.init failed")
	end
end)

-- 订阅IOT封装透传出的接收消息事件
sys.subscribe(iot.event_recv_name(), function(topic, payload, metas)
	log.info("main", "mqtt recv", topic, payload, json.encode(metas))

	local msg = parse_msg(payload)
	if not msg then
		return
	end

	if topic == config.MQTT.getTopic then
		local message_id = to_message_id(msg)
		local req = msg.dp
		local reply_dp = build_get_reply_dp(req)
		local ok = iot.publish_get_reply(message_id, true, reply_dp, nil, nil, msg.deviceId)
		log.info("main", "dp/get reply", ok, message_id, json.encode(reply_dp))
	elseif topic == config.MQTT.setTopic then
		local message_id = to_message_id(msg)
		local changed = apply_set_dp(msg.dp)
		local ok = iot.publish_set_reply(message_id, true, changed)
		log.info("main", "dp/set reply", ok, message_id, json.encode(changed))
	end
end)

-- 订阅连接状态事件
sys.subscribe(iot.event_conn_name(), function()
	log.info("main", "mqtt connected event")
end)

sys.subscribe(iot.event_disc_name(), function(code)
	log.info("main", "mqtt disconnected", code)
end)

-- 按指定JSON格式发送测试数据，仅传入dp参数
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
			log.info("main", "publish_dp result", ok, temp, fanSpeed, door, humidity, err, now)
		end
		sys.wait(10000)
	end
end)




sys.run()