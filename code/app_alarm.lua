local app_alarm = {}

local ALARM_ORDER = {
	"door_open_timeout",
	"temp1_low",
	"temp1_high",
	"temp2_low",
	"temp2_high",
	"temp_diff_high",
	"current_low",
	"current_high",
	"pressure_diff_low",
	"pressure_diff_high"
}

local function log_info(...)
	if log and type(log.info) == "function" then
		log.info(...)
	end
end

local function format_number(value)
	if type(value) ~= "number" then
		return tostring(value)
	end

	if value == math.floor(value) then
		return string.format("%.0f", value)
	end

	return string.format("%.1f", value)
end

local function clone_table(source)
	local target = {}

	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		target[key] = value
	end

	return target
end

local function is_ok(entry)
	return type(entry) == "table" and entry.ok == true
end

local function build_segments(snapshot, values, new_alarm_map)
	local segments = {}

	for i = 1, #ALARM_ORDER do
		local key = ALARM_ORDER[i]
		if new_alarm_map[key] then
			if key == "door_open_timeout" then
				segments[#segments + 1] = "门持续打开超时"
			elseif key == "temp1_low" then
				segments[#segments + 1] = "温度1低温=" .. format_number(values.temp1)
			elseif key == "temp1_high" then
				segments[#segments + 1] = "温度1高温=" .. format_number(values.temp1)
			elseif key == "temp2_low" then
				segments[#segments + 1] = "温度2低温=" .. format_number(values.temp2)
			elseif key == "temp2_high" then
				segments[#segments + 1] = "温度2高温=" .. format_number(values.temp2)
			elseif key == "temp_diff_high" then
				segments[#segments + 1] = "温差异常=" .. format_number(values.temp_diff)
			elseif key == "current_low" then
				segments[#segments + 1] = "电流低=" .. format_number(values.current_sensor_mv)
			elseif key == "current_high" then
				segments[#segments + 1] = "电流高=" .. format_number(values.current_sensor_mv)
			elseif key == "pressure_diff_low" or key == "pressure_diff_high" then
				segments[#segments + 1] = "压差异常=" .. format_number(values.pressure_diff)
			end
		end
	end

	if #segments == 0 then
		return ""
	end

	segments[#segments + 1] = "时间=" .. tostring(snapshot.timestamp or "")
	return "告警:" .. table.concat(segments, "; ")
end

local function join_alarm_keys(active_map)
	local keys = {}

	for i = 1, #ALARM_ORDER do
		local key = ALARM_ORDER[i]
		if active_map[key] then
			keys[#keys + 1] = key
		end
	end

	return table.concat(keys, ",")
end

function app_alarm.evaluate(cfg, snapshot, runtime, now_ms)
	local active_map = {}
	local previous_active = type(runtime) == "table" and runtime.active_map or {}
	local door_open_since_ms = type(runtime) == "table" and runtime.door_open_since_ms or nil
	local new_alarm_keys = {}
	local new_alarm_map = {}
	local values = {}
	local temp1 = snapshot and snapshot.temp_hum and snapshot.temp_hum[0]
	local temp2 = snapshot and snapshot.temp_hum and snapshot.temp_hum[1]
	local pressure1 = snapshot and snapshot.pressure and snapshot.pressure[1]
	local pressure2 = snapshot and snapshot.pressure and snapshot.pressure[2]

	if snapshot and snapshot.door_open then
		if type(door_open_since_ms) ~= "number" then
			door_open_since_ms = now_ms
		end
		if type(cfg) == "table" and type(cfg.door_open_warn_ms) == "number" and (now_ms - door_open_since_ms) >= cfg.door_open_warn_ms then
			active_map.door_open_timeout = true
		end
	else
		door_open_since_ms = nil
	end

	if is_ok(temp1) and type(temp1.temperature) == "number" then
		values.temp1 = temp1.temperature
		if type(cfg) == "table" and type(cfg.temp_low) == "number" and temp1.temperature < cfg.temp_low then
			active_map.temp1_low = true
		end
		if type(cfg) == "table" and type(cfg.temp_high) == "number" and temp1.temperature > cfg.temp_high then
			active_map.temp1_high = true
		end
	end

	if is_ok(temp2) and type(temp2.temperature) == "number" then
		values.temp2 = temp2.temperature
		if type(cfg) == "table" and type(cfg.temp_low) == "number" and temp2.temperature < cfg.temp_low then
			active_map.temp2_low = true
		end
		if type(cfg) == "table" and type(cfg.temp_high) == "number" and temp2.temperature > cfg.temp_high then
			active_map.temp2_high = true
		end
	end

	if type(values.temp1) == "number" and type(values.temp2) == "number" then
		values.temp_diff = math.abs(values.temp2 - values.temp1)
		if type(cfg) == "table" and type(cfg.temp_diff_high) == "number" and values.temp_diff > cfg.temp_diff_high then
			active_map.temp_diff_high = true
		end
	end

	if snapshot and type(snapshot.current_sensor_mv) == "number" then
		values.current_sensor_mv = snapshot.current_sensor_mv
		if type(cfg) == "table" and type(cfg.current_low) == "number" and snapshot.current_sensor_mv < cfg.current_low then
			active_map.current_low = true
		end
		if type(cfg) == "table" and type(cfg.current_high) == "number" and snapshot.current_sensor_mv > cfg.current_high then
			active_map.current_high = true
		end
	end

	if is_ok(pressure1) and type(pressure1.pressure) == "number" and is_ok(pressure2) and type(pressure2.pressure) == "number" then
		values.pressure_diff = math.abs(pressure2.pressure - pressure1.pressure)
		if type(cfg) == "table" and type(cfg.pressure_diff_low) == "number" and values.pressure_diff < cfg.pressure_diff_low then
			active_map.pressure_diff_low = true
		end
		if type(cfg) == "table" and type(cfg.pressure_diff_high) == "number" and values.pressure_diff > cfg.pressure_diff_high then
			active_map.pressure_diff_high = true
		end
	end

	for i = 1, #ALARM_ORDER do
		local key = ALARM_ORDER[i]
		if active_map[key] and previous_active[key] ~= true then
			new_alarm_keys[#new_alarm_keys + 1] = key
			new_alarm_map[key] = true
		end
	end

	local result = {
		active_map = clone_table(active_map),
		new_alarm_keys = new_alarm_keys,
		should_send_sms = #new_alarm_keys > 0,
		sms_text = build_segments(snapshot or {}, values, new_alarm_map),
		runtime = {
			active_map = clone_table(active_map),
			door_open_since_ms = door_open_since_ms
		}
	}

	if result.should_send_sms then
		log_info("app_alarm", "命中新告警", table.concat(new_alarm_keys, ","), result.sms_text)
	elseif next(active_map) ~= nil then
		log_info("app_alarm", "告警持续中，本轮不重复发送", join_alarm_keys(active_map))
	else
		log_info("app_alarm", "本轮无告警")
	end

	return result
end

return app_alarm
