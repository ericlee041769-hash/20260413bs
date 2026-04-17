local calls = {}
local errors = {}

_G.log = {
	error = function(...)
		errors[#errors + 1] = { ... }
	end
}

_G.i2c = {
	FAST = 400,
	SLOW = 100,
	PLUS = 1000,
	_exist_map = {
		[0] = true,
		[1] = true
	},
	_setup_result = {
		[0] = 1,
		[1] = 1
	},
	_read_result = {
		[0] = {
			[0x44] = { true, 501, 252 },
			[0x45] = { false, nil, nil }
		},
		[1] = {
			[0x44] = { true, 603, 268 },
			[0x45] = { false, nil, nil }
		}
	},
	exist = function(id)
		calls[#calls + 1] = { fn = "exist", id = id }
		return i2c._exist_map[id] == true
	end,
	setup = function(id, speed, polling)
		calls[#calls + 1] = { fn = "setup", id = id, speed = speed, polling = polling }
		return i2c._setup_result[id] or 0
	end,
	readSHT30 = function(id, addr)
		local bus = i2c._read_result[id] or {}
		local data = bus[addr] or { false, nil, nil }
		calls[#calls + 1] = { fn = "readSHT30", id = id, addr = addr }
		return data[1], data[2], data[3]
	end
}

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

local function assert_nil(value, message)
	if value ~= nil then
		error(message .. ": expected nil, got " .. tostring(value))
	end
end

local function clear_records()
	calls = {}
	errors = {}
	i2c._exist_map[0] = true
	i2c._exist_map[1] = true
	i2c._setup_result[0] = 1
	i2c._setup_result[1] = 1
	i2c._read_result[0] = {
		[0x44] = { true, 501, 252 },
		[0x45] = { false, nil, nil }
	}
	i2c._read_result[1] = {
		[0x44] = { true, 603, 268 },
		[0x45] = { false, nil, nil }
	}
end

local module_loader, load_err = loadfile("gsht30.lua")
assert(module_loader, load_err)
local gsht30 = module_loader()

assert_equal(gsht30.I2C0, 0, "I2C0 constant")
assert_equal(gsht30.I2C1, 1, "I2C1 constant")
assert_equal(gsht30.DEFAULT_ADDR, 0x44, "DEFAULT_ADDR constant")

clear_records()
assert_true(gsht30.init(), "init default return")
assert_equal(#calls, 4, "init default call count")
assert_equal(calls[1].fn, "exist", "init default exist0 fn")
assert_equal(calls[1].id, gsht30.I2C0, "init default exist0 id")
assert_equal(calls[2].fn, "exist", "init default exist1 fn")
assert_equal(calls[2].id, gsht30.I2C1, "init default exist1 id")
assert_equal(calls[3].fn, "setup", "init default setup0 fn")
assert_equal(calls[3].id, gsht30.I2C0, "init default setup0 id")
assert_equal(calls[3].speed, i2c.FAST, "init default setup0 speed")
assert_equal(calls[4].fn, "setup", "init default setup1 fn")
assert_equal(calls[4].id, gsht30.I2C1, "init default setup1 id")
assert_equal(calls[4].speed, i2c.FAST, "init default setup1 speed")

clear_records()
assert_true(gsht30.init(i2c.SLOW), "init custom speed return")
assert_equal(calls[3].speed, i2c.SLOW, "init custom speed setup0")
assert_equal(calls[4].speed, i2c.SLOW, "init custom speed setup1")

clear_records()
i2c._exist_map[1] = false
assert_false(gsht30.init(), "init missing bus return")
assert_equal(#errors, 1, "init missing bus log count")

clear_records()
i2c._setup_result[1] = 0
assert_false(gsht30.init(), "init setup fail return")
assert_equal(#errors, 1, "init setup fail log count")

clear_records()
local ok0, hum0, temp0 = gsht30.read(gsht30.I2C0)
assert_true(ok0, "read i2c0 result")
assert_equal(hum0, 501, "read i2c0 humidity")
assert_equal(temp0, 252, "read i2c0 temperature")
assert_equal(#calls, 1, "read i2c0 call count")
assert_equal(calls[1].fn, "readSHT30", "read i2c0 fn")
assert_equal(calls[1].id, gsht30.I2C0, "read i2c0 id")
assert_equal(calls[1].addr, gsht30.DEFAULT_ADDR, "read i2c0 addr")

clear_records()
local ok1, hum1, temp1 = gsht30.read(gsht30.I2C1, 0x45)
assert_false(ok1, "read i2c1 result")
assert_nil(hum1, "read i2c1 humidity")
assert_nil(temp1, "read i2c1 temperature")
assert_equal(calls[1].addr, 0x45, "read i2c1 custom addr")

clear_records()
local invalid_ok, invalid_hum, invalid_temp = gsht30.read(2)
assert_false(invalid_ok, "read invalid bus result")
assert_nil(invalid_hum, "read invalid bus humidity")
assert_nil(invalid_temp, "read invalid bus temperature")
assert_equal(#errors, 1, "read invalid bus log count")

clear_records()
i2c._read_result[1][0x44] = { false, nil, nil }
i2c._read_result[1][0x45] = { true, 611, 271 }
local fallback_ok, fallback_hum, fallback_temp = gsht30.read(gsht30.I2C1)
assert_true(fallback_ok, "read fallback result")
assert_equal(fallback_hum, 611, "read fallback humidity")
assert_equal(fallback_temp, 271, "read fallback temperature")
assert_equal(#calls, 2, "read fallback call count")
assert_equal(calls[1].addr, 0x44, "read fallback first addr")
assert_equal(calls[2].addr, 0x45, "read fallback second addr")

clear_records()
local all = gsht30.read_all()
assert_true(all[gsht30.I2C0].ok, "read_all i2c0 result")
assert_equal(all[gsht30.I2C0].humidity, 501, "read_all i2c0 humidity")
assert_equal(all[gsht30.I2C0].temperature, 252, "read_all i2c0 temperature")
assert_true(all[gsht30.I2C1].ok, "read_all i2c1 result")
assert_equal(all[gsht30.I2C1].humidity, 603, "read_all i2c1 humidity")
assert_equal(all[gsht30.I2C1].temperature, 268, "read_all i2c1 temperature")
assert_equal(#calls, 2, "read_all call count")

print("gsht30_test.lua: PASS")
