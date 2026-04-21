local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local loader, load_err = loadfile("config.lua")
assert(loader, load_err)
local config = loader()

assert_equal(config.RUNTIME_DEFAULTS.airlbs_project_id, "lvU4QJ", "default airlbs project id")
assert_equal(config.RUNTIME_DEFAULTS.airlbs_project_key, "hbHtgCRY8OUvCqEC3NEyLZb5CS0w7oHV", "default airlbs project key")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.airlbs_project_id, true, "airlbs project id should stay mutable")
assert_equal(config.RUNTIME_MUTABLE_FIELDS.airlbs_project_key, true, "airlbs project key should stay mutable")

print("config_test.lua: PASS")
