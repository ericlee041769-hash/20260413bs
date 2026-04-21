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
					dp = { "sample_interval_ms", "latest" }
				}
			end
			if payload == "set_payload" then
				return {
					messageId = "set-1",
					dp = {
						report_interval_ms = 15000
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
			sample_interval_ms = 10000,
			report_interval_ms = 10000
		}
	end,
	update = function(changes)
		return changes
	end
}

local fake_app_state = {
	get_latest = function()
		return {
			timestamp = "2026-04-21 12:00:00",
			battery_mv = 3800
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
}) == true, "gmqtt should publish provided snapshot")
assert(published_dp[1].battery_mv == 3800, "published snapshot should use real data")

subscriptions["IOT_MQTT_RECV"]("get/topic", "get_payload", {})
assert(get_replies[1].message_id == "get-1", "get reply message id")
assert(get_replies[1].dp.sample_interval_ms == 10000, "get reply config value")
assert(get_replies[1].dp.latest.timestamp == "2026-04-21 12:00:00", "get reply latest snapshot")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload", {})
assert(set_replies[1].message_id == "set-1", "set reply message id")
assert(set_replies[1].dp.report_interval_ms == 15000, "set reply applied value")

print("gmqtt_test.lua: PASS")
