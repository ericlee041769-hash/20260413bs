_G.gadc = {
	read_battery = function()
		return 3800, 56
	end,
	read_wcs1500_adc0 = function()
		return 1234, 500, 1000
	end
}

_G.ggpio = {
	get_door_state = function()
		return false
	end
}

_G.gsht30 = {
	I2C0 = 0,
	I2C1 = 1,
	read_all = function()
		return {
			[0] = { ok = true, temperature = 25.2, humidity = 50.1 },
			[1] = { ok = true, temperature = 26.8, humidity = 60.3 }
		}
	end
}

_G.gbaro = {
	UART1 = 1,
	UART2 = 2,
	read_all = function()
		return {
			[1] = { ok = true, temperature = 25.8, pressure = 100.0 },
			[2] = { ok = false, error = "uart response timeout" }
		}
	end
}

_G.glbs = {
	get_location = function()
		return { 0, 0 }
	end
}

_G.os = {
	date = function()
		return "2026-04-21 12:00:00"
	end,
	time = function()
		return 1776744000
	end
}

local collect_loader, load_err = loadfile("app_collect.lua")
assert(collect_loader, load_err)
local app_collect = collect_loader()

local snapshot = app_collect.collect_once()
assert(snapshot.timestamp == "2026-04-21 12:00:00", "timestamp should be included")
assert(snapshot.timestamp_ms == 1776744000000.0, "timestamp ms should be included")
assert(snapshot.battery_mv == 3800, "battery should be included")
assert(snapshot.battery_percent == 56, "battery percent should be included")
assert(snapshot.current_raw == 1234, "current raw should be included")
assert(snapshot.current_mv == 500, "current mv should be included")
assert(snapshot.current_sensor_mv == 1000, "current sensor mv should be included")
assert(snapshot.door_open == false, "door state should be included")
assert(snapshot.location[1] == 0, "default location lat should exist")
assert(snapshot.location[2] == 0, "default location lng should exist")
assert(snapshot.temp_hum[0].temperature == 25.2, "temperature snapshot should be included")
assert(snapshot.pressure[1].pressure == 100.0, "pressure snapshot should be included")
assert(snapshot.pressure[2].ok == false, "partial failure should be preserved")

print("app_collect_test.lua: PASS")
