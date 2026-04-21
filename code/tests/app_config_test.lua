local fake_store = {}

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_nil(actual, message)
	if actual ~= nil then
		error(string.format("%s: expected nil, got %s", message, tostring(actual)))
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

_G.log = {
	error = function() end
}

local config_loader, load_err = loadfile("app_config.lua")
assert(config_loader, load_err)
local app_config = config_loader()

local cfg = app_config.load()
assert_equal(cfg.sample_interval_ms, 10000, "default sample interval")
assert_equal(cfg.report_interval_ms, 10000, "default report interval")
assert_equal(cfg.airlbs_timeout, 10000, "default airlbs timeout")

local updated = app_config.update({
	report_interval_ms = 15000,
	temp_high = 60,
	unknown_key = 1,
	current_low = "bad"
})
assert_equal(updated.report_interval_ms, 15000, "updated report interval")
assert_equal(updated.temp_high, 60, "updated temp high")
assert_nil(updated.unknown_key, "unknown key should be ignored")
assert_nil(updated.current_low, "wrong type should be ignored")

local reloaded = app_config.load()
assert_equal(reloaded.report_interval_ms, 15000, "persisted report interval")
assert_equal(reloaded.temp_high, 60, "persisted temp high")
assert_equal(reloaded.current_low, 0, "invalid current low should not persist")

print("app_config_test.lua: PASS")
