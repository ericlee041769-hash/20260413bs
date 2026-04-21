local subscriptions = {}
local task_queue = {}
local published_dp = {}
local get_replies = {}
local set_replies = {}

local fake_sys = {
	subscribe = function(event_name, handler)
		subscriptions[event_name] = handler
	end,
	taskInit = function(fn)
		task_queue[#task_queue + 1] = fn
	end,
	waitUntil = function()
		return false
	end
}

local fake_config = {
	MQTT = {
		getTopic = "get/topic",
		setTopic = "set/topic"
	}
}

local fake_iot = {
	event_recv_name = function()
		return "IOT_MQTT_RECV"
	end,
	event_conn_name = function()
		return "IOT_MQTT_CONNECTED"
	end,
	event_disc_name = function()
		return "IOT_MQTT_DISCONNECTED"
	end,
	publish_dp = function(payload)
		published_dp[#published_dp + 1] = payload
		return true
	end,
	publish_get_reply = function(message_id, success, dp)
		get_replies[#get_replies + 1] = {
			message_id = message_id,
			success = success,
			dp = dp
		}
		return true
	end,
	publish_set_reply = function(message_id, success, dp)
		set_replies[#set_replies + 1] = {
			message_id = message_id,
			success = success,
			dp = dp
		}
		return true
	end
}

local env = {
	_G = nil,
	require = function(name)
		if name == "sys" then
			return fake_sys
		end
		if name == "config" then
			return fake_config
		end
		if name == "iot" then
			return fake_iot
		end
		error("unexpected require: " .. tostring(name))
	end,
	json = {
		decode = function(payload)
			if payload == "get_payload" then
				return {
					messageId = "get-1",
					dp = { "temp", "humidity", "temp2", "humidity2", "door", "err", "time", "phonenum", "tempdiff", "lpoint" }
				}
			end
			if payload == "set_payload" then
				return {
					messageId = "set-1",
					dp = {
						phonenum = "13800138000",
						temp = 99.9
					}
				}
			end
			if payload == "set_payload_readonly" then
				return {
					messageId = "set-2",
					dp = {
						temp = 88.8,
						door = true
					}
				}
			end
			return {}
		end,
		encode = function()
			return "{}"
		end
	},
	log = {
		info = function() end,
		error = function() end
	}
}

env._G = env
setmetatable(env, { __index = _G })

local gmqtt_loader, load_err = loadfile("gmqtt.lua", "t", env)
assert(gmqtt_loader, load_err)
local gmqtt = gmqtt_loader()

local fake_app_config = {
	get = function()
		return {
			alarm_sms_phone = "15025376653"
		}
	end,
	update = function(changes)
		if changes.alarm_sms_phone then
			return {
				alarm_sms_phone = changes.alarm_sms_phone
			}
		end

		return {}
	end
}

local fake_app_state = {
	get_latest = function()
		return {
			timestamp = "2026-04-21 12:00:00",
			door_open = true,
			err = true,
			location = { 31.1354542, 121.5423279 },
			temp_hum = {
				[0] = { ok = true, temperature = 25.2, humidity = 50.1 },
				[1] = { ok = true, temperature = 26.8, humidity = 60.3 }
			}
		}
	end
}

assert(gmqtt.start({
	app_config = fake_app_config,
	app_state = fake_app_state
}) == true, "gmqtt should start with services")
assert(#task_queue == 1, "gmqtt should only create the connection task")

assert(gmqtt.publish_snapshot({
	timestamp = "2026-04-21 12:00:00",
	battery_mv = 3800
}) == false, "gmqtt should skip publish before mqtt ready")
assert(#published_dp == 0, "publish should be skipped before mqtt ready")

subscriptions["IOT_MQTT_CONNECTED"]()
assert(gmqtt.publish_snapshot({
	timestamp = "2026-04-21 12:00:00",
	door_open = true,
	err = true,
	location = { 31.1354542, 121.5423279 },
	temp_hum = {
		[0] = { ok = true, temperature = 25.2, humidity = 50.1 },
		[1] = { ok = true, temperature = 26.8, humidity = 60.3 }
	}
}) == true, "gmqtt should publish provided snapshot after mqtt ready")
assert(published_dp[1].temp == 25.2, "published dp should expose temp")
assert(published_dp[1].humidity == 50.1, "published dp should expose humidity")
assert(published_dp[1].temp2 == 26.8, "published dp should expose temp2")
assert(published_dp[1].humidity2 == 60.3, "published dp should expose humidity2")
assert(published_dp[1].door == true, "published dp should expose door")
assert(published_dp[1].err == true, "published dp should expose err")
assert(published_dp[1].time == "2026-04-21 12:00:00", "published dp should expose time")
assert(published_dp[1].phonenum == "15025376653", "published dp should expose phonenum")
assert(published_dp[1].tempdiff == 1.6, "published dp should expose tempdiff")
assert(published_dp[1].lpoint == "31.1354542,121.5423279", "published dp should expose lpoint")

subscriptions["IOT_MQTT_DISCONNECTED"](-1)
assert(gmqtt.publish_snapshot({
	timestamp = "2026-04-21 12:00:00",
	door_open = true
}) == false, "gmqtt should skip publish after mqtt disconnected")

subscriptions["IOT_MQTT_RECV"]("get/topic", "get_payload", {})
assert(get_replies[1].message_id == "get-1", "get reply message id")
assert(get_replies[1].dp.temp == 25.2, "get reply should expose temp")
assert(get_replies[1].dp.humidity == 50.1, "get reply should expose humidity")
assert(get_replies[1].dp.temp2 == 26.8, "get reply should expose temp2")
assert(get_replies[1].dp.humidity2 == 60.3, "get reply should expose humidity2")
assert(get_replies[1].dp.door == true, "get reply should expose door")
assert(get_replies[1].dp.err == true, "get reply should expose err")
assert(get_replies[1].dp.time == "2026-04-21 12:00:00", "get reply should expose time")
assert(get_replies[1].dp.phonenum == "15025376653", "get reply should expose phonenum")
assert(get_replies[1].dp.tempdiff == 1.6, "get reply should expose tempdiff")
assert(get_replies[1].dp.lpoint == "31.1354542,121.5423279", "get reply should expose lpoint")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload", {})
assert(set_replies[1].message_id == "set-1", "set reply message id")
assert(set_replies[1].dp.phonenum == "13800138000", "set reply should echo accepted phonenum")
assert(set_replies[1].dp.temp == nil, "set reply should ignore readonly temp")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload_readonly", {})
assert(set_replies[2].message_id == "set-2", "second set reply message id")
assert(next(set_replies[2].dp) == nil, "set reply should be empty when nothing is accepted")

print("gmqtt_test.lua: PASS")
