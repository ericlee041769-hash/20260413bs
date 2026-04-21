local fake_store = {}

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

_G.fskv = {
	get = function(key)
		return fake_store[key]
	end,
	set = function(key, value)
		fake_store[key] = value
		return true
	end
}

local state_loader, load_err = loadfile("app_state.lua")
assert(state_loader, load_err)
local app_state = state_loader()

local latest = app_state.save_latest({ timestamp = "2026-04-21 12:00:00", battery_mv = 3800 })
assert_equal(latest.timestamp, "2026-04-21 12:00:00", "saved timestamp")
assert_equal(latest.battery_mv, 3800, "saved battery mv")

local restored = app_state.get_latest()
assert_equal(restored.timestamp, "2026-04-21 12:00:00", "restored timestamp")
assert_equal(restored.battery_mv, 3800, "restored battery mv")

print("app_state_test.lua: PASS")
