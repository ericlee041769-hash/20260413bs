local request_calls = {}
local request_results = {}
local error_logs = {}
local current_time = 100

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
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

local before_init = glbs.get_location()
assert_location(before_init, 0, 0, "before init fallback")
assert_equal(#error_logs, 1, "before init should log once")

assert_false(glbs.init({}), "init should reject missing project_id")
assert_equal(#error_logs, 2, "missing project_id should log")

assert_true(glbs.init({ project_id = "demo_project" }), "init should accept valid project_id")

print("glbs_test.lua: PASS")
