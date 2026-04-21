local module_loader, load_err = loadfile("app_algorithm.lua")
assert(module_loader, load_err)
local app_algorithm = module_loader()

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_close(actual, expected, message)
	if math.abs(actual - expected) > 0.0001 then
		error(string.format("%s: expected %.4f, got %.4f", message, expected, actual))
	end
end

local runtime = nil

local first_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 10, humidity = 50 },
		[1] = { ok = true, temperature = 20, humidity = 60 }
	},
	current_sensor_mv = 100
}

local second_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 30, humidity = 70 },
		[1] = { ok = true, temperature = 40, humidity = 80 }
	},
	current_sensor_mv = 200
}

local third_snapshot = {
	temp_hum = {
		[0] = { ok = true, temperature = 20, humidity = 60 },
		[1] = { ok = true, temperature = 30, humidity = 70 }
	},
	current_sensor_mv = 300
}

local output1
output1, runtime = app_algorithm.apply(first_snapshot, runtime)
assert_equal(output1.temp_hum[0].temperature, 10, "first ch0 temperature should initialize from first sample")
assert_equal(output1.temp_hum[1].humidity, 60, "first ch1 humidity should initialize from first sample")
assert_equal(output1.current_sensor_mv, 100, "first current should initialize from first sample")

local output2
output2, runtime = app_algorithm.apply(second_snapshot, runtime)
assert_close(output2.temp_hum[0].temperature, 15.0, "second ch0 temperature should use median plus ema")
assert_close(output2.temp_hum[1].temperature, 25.0, "second ch1 temperature should use median plus ema")
assert_equal(output2.current_sensor_mv, 150, "second current should use 2-point average")

local output3
output3, runtime = app_algorithm.apply(third_snapshot, runtime)
assert_close(output3.temp_hum[0].temperature, 17.5, "third ch0 temperature should use filtered formal value")
assert_close(output3.temp_hum[0].humidity, 57.5, "third ch0 humidity should use filtered formal value")
assert_close(output3.temp_hum[1].temperature, 27.5, "third ch1 temperature should use filtered formal value")
assert_equal(output3.current_sensor_mv, 200, "third current should use 3-point moving average")
assert_close(runtime.temp_hum[0].filtered_temp, 17.5, "runtime should retain filtered temperature")
assert_equal(#runtime.current.window, 3, "runtime should retain current history window")

print("app_algorithm_test.lua: PASS")
