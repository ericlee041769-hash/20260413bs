local app_collect = {}

local gadc = rawget(_G, "gadc") or require("gadc")
local ggpio = rawget(_G, "ggpio") or require("ggpio")
local gsht30 = rawget(_G, "gsht30") or require("gsht30")
local gbaro = rawget(_G, "gbaro") or require("gbaro")
local glbs = rawget(_G, "glbs") or require("glbs")

local function log_info(...)
	if log and type(log.info) == "function" then
		log.info(...)
	end
end

local function safe_json_encode(value)
	if json and type(json.encode) == "function" then
		local ok, encoded = pcall(json.encode, value)
		if ok then
			return encoded
		end
	end

	return tostring(value)
end

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
	if type(glbs) == "table" and type(glbs.is_ready) == "function" and not glbs.is_ready() then
		log_info("app_collect", "AirLBS未初始化，使用默认坐标")
		return { 0, 0 }
	end

	local ok, location = safe_call(glbs and glbs.get_location)
	if not ok or type(location) ~= "table" then
		log_info("app_collect", "AirLBS读取失败，使用默认坐标", ok, type(location))
		return { 0, 0 }
	end

	log_info("app_collect", "AirLBS定位结果", location[1] or 0, location[2] or 0)
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
	local now_seconds = os.time() or 0
	local battery_mv, battery_percent = read_battery()
	local current_raw, current_mv, current_sensor_mv = read_current()
	local snapshot = {
		timestamp = os.date("%Y-%m-%d %H:%M:%S", now_seconds),
		timestamp_ms = now_seconds * 1000.0,
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

	log_info("app_collect", "采集完成", safe_json_encode(snapshot))
	return snapshot
end

return app_collect
