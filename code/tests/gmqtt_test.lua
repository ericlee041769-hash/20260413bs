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
	},
	GATEWAY_CONFIG_FIELDS = {
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
					dp = { "temp", "humidity", "temp2", "humidity2", "door", "err", "time", "tempdiff", "lpoint", "pressure1", "pressure2", "pressurediff", "config" }
				}
			end
			if payload == "set_payload" then
				return {
					messageId = "set-1",
					dp = {
						config = {
							alarm_sms_phone = "13800138000",
							usb_interval_ms = 15000,
							battery_interval_ms = 90000,
							battery_prewake_ms = 12000
						},
						temp = 99.9
					}
				}
			end
			if payload == "set_payload_json" then
				return {
					messageId = "set-3",
					dp = {
						config = {
							alarm_sms_phone = "13900139000",
							battery_interval_ms = 120000,
							temp_high = 70,
							airlbs_project_id = "blocked"
						}
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

local fake_runtime_cfg = {
	usb_interval_ms = 10000,
	battery_interval_ms = 60000,
	battery_prewake_ms = 5000,
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

local fake_app_config = {
	get = function()
		return fake_runtime_cfg
	end,
	update = function(changes)
		local applied = {}

		for key, value in pairs(changes or {}) do
			if fake_config.GATEWAY_CONFIG_FIELDS[key] == true then
				fake_runtime_cfg[key] = value
				applied[key] = value
			end
		end

		return applied
	end
}

local fake_app_state = {
	get_latest = function()
		return {
			timestamp = "2026-04-21 12:00:00",
			timestamp_ms = 1776744000000.0,
			door_open = true,
			err = "门持续打开超时; 压差异常=0.7",
			location = { 31.1354542, 121.5423279 },
			pressure = {
				[1] = { ok = true, pressure = 100.0 },
				[2] = { ok = true, pressure = 100.7 }
			},
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
	timestamp_ms = 1776744000000.0,
	door_open = true,
	err = "门持续打开超时; 压差异常=0.7",
	location = { 31.1354542, 121.5423279 },
	pressure = {
		[1] = { ok = true, pressure = 100.0 },
		[2] = { ok = true, pressure = 100.7 }
	},
	temp_hum = {
		[0] = { ok = true, temperature = 25.2, humidity = 50.1 },
		[1] = { ok = true, temperature = 26.8, humidity = 60.3 }
	}
}) == true, "gmqtt should publish provided snapshot after mqtt ready")
assert(published_dp[1].temp == 25.2, "published dp should expose temp")
assert(published_dp[1].humidity == 50.1, "published dp should expose humidity")
assert(published_dp[1].temp2 == 26.8, "published dp should expose temp2")
assert(published_dp[1].humidity2 == 60.3, "published dp should expose humidity2")
assert(published_dp[1].door == false, "published dp should invert door state for gateway upload")
assert(published_dp[1].err == "门持续打开超时; 压差异常=0.7", "published dp should expose err text")
assert(published_dp[1].time == "2026-04-21 12:00:00", "published dp should expose gateway date string")
assert(published_dp[1].tempdiff == 1.6, "published dp should expose tempdiff")
assert(published_dp[1].lpoint == "31.1354542,121.5423279", "published dp should expose lpoint")
assert(published_dp[1].pressure1 == 100.0, "published dp should expose pressure1")
assert(published_dp[1].pressure2 == 100.7, "published dp should expose pressure2")
assert(published_dp[1].pressurediff == 0.7, "published dp should expose pressurediff")
assert(type(published_dp[1].config) == "table", "published dp should expose config object")
assert(published_dp[1].config.alarm_sms_phone == "15025376653", "published dp config should expose alarm sms phone")
assert(published_dp[1].config.usb_interval_ms == 10000, "published dp config should expose usb interval")
assert(published_dp[1].config.battery_interval_ms == 60000, "published dp config should expose battery interval")
assert(published_dp[1].config.battery_prewake_ms == nil, "published dp config should exclude fixed battery prewake")
assert(published_dp[1].config.airlbs_project_id == nil, "published dp config should exclude airlbs project id")

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
assert(get_replies[1].dp.door == false, "get reply should invert door state for gateway upload")
assert(get_replies[1].dp.err == "门持续打开超时; 压差异常=0.7", "get reply should expose err text")
assert(get_replies[1].dp.time == "2026-04-21 12:00:00", "get reply should expose gateway date string")
assert(get_replies[1].dp.tempdiff == 1.6, "get reply should expose tempdiff")
assert(get_replies[1].dp.lpoint == "31.1354542,121.5423279", "get reply should expose lpoint")
assert(get_replies[1].dp.pressure1 == 100.0, "get reply should expose pressure1")
assert(get_replies[1].dp.pressure2 == 100.7, "get reply should expose pressure2")
assert(get_replies[1].dp.pressurediff == 0.7, "get reply should expose pressurediff")
assert(type(get_replies[1].dp.config) == "table", "get reply should expose config object")
assert(get_replies[1].dp.config.alarm_sms_phone == "15025376653", "get reply config should expose alarm sms phone")
assert(get_replies[1].dp.config.usb_interval_ms == 10000, "get reply config should expose usb interval")
assert(get_replies[1].dp.config.battery_interval_ms == 60000, "get reply config should expose battery interval")
assert(get_replies[1].dp.config.battery_prewake_ms == nil, "get reply config should exclude fixed battery prewake")
assert(get_replies[1].dp.config.airlbs_project_id == nil, "get reply config should exclude airlbs project id")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload", {})
assert(set_replies[1].message_id == "set-1", "set reply message id")
assert(type(set_replies[1].dp.config) == "table", "set reply should return config object")
assert(set_replies[1].dp.config.alarm_sms_phone == "13800138000", "set reply config should echo accepted alarm sms phone")
assert(set_replies[1].dp.config.usb_interval_ms == 15000, "set reply config should echo accepted usb interval")
assert(set_replies[1].dp.config.battery_interval_ms == 90000, "set reply config should echo accepted battery interval")
assert(set_replies[1].dp.config.battery_prewake_ms == nil, "set reply config should ignore fixed battery prewake")
assert(set_replies[1].dp.temp == nil, "set reply should ignore readonly temp")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload_readonly", {})
assert(set_replies[2].message_id == "set-2", "second set reply message id")
assert(next(set_replies[2].dp) == nil, "set reply should be empty when nothing is accepted")

subscriptions["IOT_MQTT_RECV"]("set/topic", "set_payload_json", {})
assert(set_replies[3].message_id == "set-3", "json set reply message id")
assert(type(set_replies[3].dp.config) == "table", "json set should return config object")
assert(set_replies[3].dp.config.alarm_sms_phone == "13900139000", "json set should update alarm sms phone")
assert(set_replies[3].dp.config.battery_interval_ms == 120000, "json set should update battery interval")
assert(set_replies[3].dp.config.temp_high == 70, "json set should update temp high")
assert(set_replies[3].dp.config.airlbs_project_id == nil, "json set should ignore blocked fields")

print("gmqtt_test.lua: PASS")
