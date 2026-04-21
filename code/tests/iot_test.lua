local published_calls = {}
local encoded_payload = nil

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
	on = function() end,
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
		info = function() end,
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
	postTopic = "/demo/post"
}), "iot should init")

assert(iot.connect(), "iot should connect")
assert(iot.publish_dp({
	temp = 25.2,
	door = false
}), "publish_dp should succeed")
assert(encoded_payload.deviceId == nil, "direct dp/post should omit deviceId")
assert(encoded_payload.dp.temp == 25.2, "encoded dp should keep temp")
assert(encoded_payload.dp.door == false, "encoded dp should keep door")
assert(published_calls[1].topic == "/demo/post", "publish topic should match config")

print("iot_test.lua: PASS")
