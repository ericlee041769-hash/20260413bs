local request_calls = {}
local request_results = {}
local error_logs = {}
local current_time = 100
local network_ready = true
local wait_calls = {}
local sntp_calls = 0

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function count_wait_event(event_name)
	local count = 0

	for i = 1, #wait_calls do
		if wait_calls[i].event_name == event_name then
			count = count + 1
		end
	end

	return count
end

local function assert_true(value, message)
	if value ~= true then
		error(message .. ": expected true, got " .. tostring(value))
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message .. ": expected false, got " .. tostring(value))
	end
end

local function assert_location(actual, expected_lat, expected_lng, message)
	assert_equal(type(actual), "table", message .. " type")
	assert_equal(actual[1], expected_lat, message .. " lat")
	assert_equal(actual[2], expected_lng, message .. " lng")
end

_G.airlbs = {
	request = function(param)
		request_calls[#request_calls + 1] = param
		local next_result = request_results[1] or { false, nil }
		if #request_results > 0 then
			table.remove(request_results, 1)
		end
		return next_result[1], next_result[2]
	end
}

_G.sys = {
	waitUntil = function(event_name, timeout_ms)
		wait_calls[#wait_calls + 1] = {
			event_name = event_name,
			timeout_ms = timeout_ms
		}
		if event_name == "IP_READY" then
			network_ready = true
			return true
		end
		return false
	end
}

_G.socket = {
	dft = function()
		return 1
	end,
	adapter = function()
		if network_ready then
			return {}
		end
		return nil
	end,
	sntp = function()
		sntp_calls = sntp_calls + 1
		return true
	end
}

_G.log = {
	error = function(...)
		error_logs[#error_logs + 1] = { ... }
	end
}

_G.os = {
	time = function()
		return current_time
	end
}

local module_loader, load_err = loadfile("glbs.lua")
assert(module_loader, load_err)
local glbs = module_loader()

assert_false(glbs.is_ready(), "glbs should report not ready before init")
local before_init = glbs.get_location()
assert_location(before_init, 0, 0, "before init fallback")
assert_equal(#error_logs, 1, "before init should log once")

assert_false(glbs.init({}), "init should reject missing project_id")
assert_equal(#error_logs, 2, "missing project_id should log")

assert_true(glbs.init({ project_id = "demo_project" }), "init should accept valid project_id")
assert_true(glbs.is_ready(), "glbs should report ready after init")

request_calls = {}
request_results = {
	{ true, { lat = 31.1354542, lng = 121.5423279 } },
	{ true, { lat = 30.1234567, lng = 120.7654321 } },
	{ false, nil }
}
error_logs = {}
current_time = 100
network_ready = true
wait_calls = {}
sntp_calls = 0

assert_true(
	glbs.init({
		project_id = "demo_project",
		project_key = "demo_key",
		timeout = 15000,
		adapter = 3,
		wifi_info = {
			{ bssid = "24:32:AE:04:E1:67", rssi = -86 }
		}
	}),
	"init with request config"
)

local first_location = glbs.get_location()
assert_location(first_location, 31.1354542, 121.5423279, "first successful request")
assert_equal(#request_calls, 1, "first call should request once")
assert_equal(request_calls[1].project_id, "demo_project", "project_id should be forwarded")
assert_equal(request_calls[1].project_key, "demo_key", "project_key should be forwarded")
assert_equal(request_calls[1].timeout, 15000, "timeout should be forwarded")
assert_equal(request_calls[1].adapter, 3, "adapter should be forwarded")
assert_equal(request_calls[1].wifi_info[1].bssid, "24:32:AE:04:E1:67", "wifi_info should be forwarded")

current_time = 130
local cached_location = glbs.get_location()
assert_location(cached_location, 31.1354542, 121.5423279, "second call should use cache inside 60 seconds")
assert_equal(#request_calls, 1, "cached call should not request again")

current_time = 161
local refreshed_location = glbs.get_location()
assert_location(refreshed_location, 30.1234567, 120.7654321, "refresh after 60 seconds")
assert_equal(#request_calls, 2, "refresh should request again")

current_time = 222
local failed_refresh_location = glbs.get_location()
assert_location(failed_refresh_location, 30.1234567, 120.7654321, "failed refresh should return last success")
assert_equal(#request_calls, 3, "failed refresh should still attempt request")

assert_true(glbs.init({ project_id = "fresh_project" }), "re-init should reset state")
assert_true(glbs.is_ready(), "glbs should stay ready after re-init")
current_time = 300
request_calls = {}
request_results = {
	{ false, nil }
}

local first_failure_location = glbs.get_location()
assert_location(first_failure_location, 0, 0, "first failure without cache should return zero")
assert_equal(#request_calls, 1, "first failure should still attempt request")
assert_equal(request_calls[1].timeout, 10000, "default timeout should be 10000")

assert_true(glbs.init({ project_id = "demo_project", project_key = "demo_key", timeout = 15000 }), "init for network wait and payload parse")
request_calls = {}
request_results = {
	{ true, { location = "121.5423279,31.1354542" } }
}
error_logs = {}
current_time = 400
network_ready = false
wait_calls = {}
sntp_calls = 0

local parsed_location = glbs.get_location()
assert_location(parsed_location, 31.1354542, 121.5423279, "string location payload should be parsed")
assert_equal(count_wait_event("IP_READY"), 1, "location request should wait for IP_READY when network is not ready")
assert_equal(wait_calls[1].event_name, "IP_READY", "wait should subscribe to IP_READY")
assert_equal(wait_calls[1].timeout_ms, 1000, "wait should poll IP_READY every second")
assert_equal(sntp_calls, 1, "location request should trigger sntp once after network becomes ready")
assert_equal(#request_calls, 1, "parsed location should still issue exactly one request")

print("glbs_test.lua: PASS")
