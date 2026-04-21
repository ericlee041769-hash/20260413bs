local published_calls = {}
local encoded_payload = nil
local infos = {}
local mqtt_callback = nil

local function find_info_log(...)
	local expected = { ... }

	for i = 1, #infos do
		local matched = true
		for j = 1, #expected do
			if infos[i][j] ~= expected[j] then
				matched = false
				break
			end
		end
		if matched then
			return infos[i]
		end
	end

	return nil
end

local fake_client = {
	ready = function()
		return true
	end,
	publish = function(_, topic, body, qos, retain)
		published_calls[#published_calls + 1] = {
			topic = topic,
			body = body,
			qos = qos,
			retain = retain
		}
		return 1
	end,
	close = function() end,
	debug = function() end,
	auth = function()
		return true
	end,
	on = function(_, cb)
		mqtt_callback = cb
	end,
	connect = function()
		return true
	end
}

local env = {
	_G = nil,
	mqtt = {
		create = function()
			return fake_client
		end
	},
	json = {
		encode = function(payload)
			encoded_payload = payload
			return "encoded"
		end
	},
	sys = {
		publish = function() end
	},
	log = {
		info = function(...)
			infos[#infos + 1] = { ... }
		end,
		error = function() end
	},
	os = {
		time = function()
			return 100
		end
	},
	math = math,
	tostring = tostring,
	type = type
}

env._G = env
setmetatable(env, { __index = _G })

local loader, load_err = loadfile("iot.lua", "t", env)
assert(loader, load_err)
local iot = loader()

assert(iot.init({
	host = "demo-host",
	port = 1883,
	clientId = "demo-device",
	username = "demo-product",
	password = "demo-password",
	postTopic = "/demo/post",
	getReplyTopic = "/demo/get/reply",
	setReplyTopic = "/demo/set/reply"
}), "iot should init")

assert(iot.connect(), "iot should connect")
assert(iot.publish_dp({
	temp = 25.2,
	door = false
}), "publish_dp should succeed")
assert(encoded_payload.deviceId == "demo-device", "direct dp/post should include deviceId")
assert(encoded_payload.dp.temp == 25.2, "encoded dp should keep temp")
assert(encoded_payload.dp.door == false, "encoded dp should keep door")
assert(published_calls[1].topic == "/demo/post", "publish topic should match config")
assert(find_info_log("iot.publish", "/demo/post", "encoded") ~= nil, "publish should log actual mqtt upload")
assert(find_info_log("iot.publish", "queued", "/demo/post", 1) ~= nil, "publish should log queued message id")

assert(type(mqtt_callback) == "function", "mqtt callback should be registered")
mqtt_callback(fake_client, "sent", 1, nil, nil)
assert(find_info_log("iot.mqtt_cb", "sent", 1, "/demo/post") ~= nil, "sent callback should log matching topic")

assert(iot.publish_get_reply("mid-1", true, {
	config = {
		usb_interval_ms = 10000
	}
}), "publish_get_reply should succeed")
assert(published_calls[2].topic == "/demo/get/reply", "get reply topic should match config")
assert(encoded_payload.messageId == "mid-1", "get reply should keep message id")
assert(encoded_payload.success == true, "get reply should keep success")
assert(encoded_payload.deviceId == "demo-device", "get reply should default device id")
assert(encoded_payload.timestamp == 100000.0, "get reply timestamp should be millisecond precision")
assert(math.type(encoded_payload.timestamp) == "float", "get reply timestamp should use overflow-safe float representation")
assert(encoded_payload.dp.config.usb_interval_ms == 10000, "get reply should keep dp payload")

assert(iot.publish_set_reply("mid-2", true, {
	config = {
		battery_interval_ms = 60000
	}
}), "publish_set_reply should succeed")
assert(published_calls[3].topic == "/demo/set/reply", "set reply topic should match config")
assert(encoded_payload.messageId == "mid-2", "set reply should keep message id")
assert(encoded_payload.success == true, "set reply should keep success")
assert(encoded_payload.timestamp == 100000.0, "set reply timestamp should be millisecond precision")
assert(math.type(encoded_payload.timestamp) == "float", "set reply timestamp should use overflow-safe float representation")
assert(encoded_payload.dp.config.battery_interval_ms == 60000, "set reply should keep dp payload")

print("iot_test.lua: PASS")
