local app_collect = {}

local function safe_call(fn, ...)
	if type(fn) ~= "function" then
		return false
	end

	return pcall(fn, ...)
end

local function read_battery()
	local ok, battery_mv, battery_percent = safe_call(gadc and gadc.read_battery)
	if not ok then
		return nil, nil
	end

	return battery_mv, battery_percent
end

local function read_current()
	local ok, current_raw, current_mv, current_sensor_mv = safe_call(gadc and gadc.read_wcs1500_adc0)
	if not ok then
		return nil, nil, nil
	end

	return current_raw, current_mv, current_sensor_mv
end

local function read_door_state()
	local ok, door_open = safe_call(ggpio and ggpio.get_door_state)
	if not ok then
		return false
	end

	return door_open and true or false
end

local function read_location()
	local ok, location = safe_call(glbs and glbs.get_location)
	if not ok or type(location) ~= "table" then
		return { 0, 0 }
	end

	return { location[1] or 0, location[2] or 0 }
end

local function read_temp_hum()
	local ok, result = safe_call(gsht30 and gsht30.read_all)
	if not ok or type(result) ~= "table" then
		return {}
	end

	return result
end

local function read_pressure()
	local ok, result = safe_call(gbaro and gbaro.read_all)
	if not ok or type(result) ~= "table" then
		return {}
	end

	return result
end

function app_collect.collect_once()
	local battery_mv, battery_percent = read_battery()
	local current_raw, current_mv, current_sensor_mv = read_current()

	return {
		timestamp = os.date("%Y-%m-%d %H:%M:%S"),
		battery_mv = battery_mv,
		battery_percent = battery_percent,
		current_raw = current_raw,
		current_mv = current_mv,
		current_sensor_mv = current_sensor_mv,
		door_open = read_door_state(),
		location = read_location(),
		temp_hum = read_temp_hum(),
		pressure = read_pressure()
	}
end

return app_collect
