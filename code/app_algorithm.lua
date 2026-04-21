local app_algorithm = {}

local WINDOW_SIZE = 3
local EMA_ALPHA = 0.5

local function clone_table(source)
	if type(source) ~= "table" then
		return source
	end

	local target = {}
	for key, value in pairs(source) do
		target[key] = clone_table(value)
	end
	return target
end

local function ensure_table(value)
	if type(value) == "table" then
		return value
	end
	return {}
end

local function append_window(window, value)
	local next_window = {}
	local start_index = 1

	if type(window) == "table" then
		start_index = math.max(1, #window - WINDOW_SIZE + 2)
		for i = start_index, #window do
			next_window[#next_window + 1] = window[i]
		end
	end

	next_window[#next_window + 1] = value
	return next_window
end

local function median(window)
	local sorted = {}
	local count

	if type(window) ~= "table" or #window == 0 then
		return nil
	end

	for i = 1, #window do
		sorted[i] = window[i]
	end
	table.sort(sorted)
	count = #sorted

	if (count % 2) == 1 then
		return sorted[(count + 1) / 2]
	end

	return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

local function ema(last_value, current_value)
	if type(current_value) ~= "number" then
		return last_value
	end
	if type(last_value) ~= "number" then
		return current_value
	end
	return EMA_ALPHA * current_value + (1 - EMA_ALPHA) * last_value
end

local function average(window)
	local total = 0

	if type(window) ~= "table" or #window == 0 then
		return nil
	end

	for i = 1, #window do
		total = total + window[i]
	end
	return total / #window
end

local function process_temp_hum_channel(entry, runtime_entry)
	local next_entry = clone_table(entry)
	local next_runtime_entry = ensure_table(clone_table(runtime_entry))
	local temp_med
	local hum_med

	if type(entry) ~= "table" or entry.ok ~= true then
		return next_entry, next_runtime_entry
	end

	if type(entry.temperature) == "number" then
		next_runtime_entry.temp_window = append_window(next_runtime_entry.temp_window, entry.temperature)
		temp_med = median(next_runtime_entry.temp_window)
		next_runtime_entry.filtered_temp = ema(next_runtime_entry.filtered_temp, temp_med)
		next_entry.temperature = next_runtime_entry.filtered_temp
	end

	if type(entry.humidity) == "number" then
		next_runtime_entry.hum_window = append_window(next_runtime_entry.hum_window, entry.humidity)
		hum_med = median(next_runtime_entry.hum_window)
		next_runtime_entry.filtered_hum = ema(next_runtime_entry.filtered_hum, hum_med)
		next_entry.humidity = next_runtime_entry.filtered_hum
	end

	return next_entry, next_runtime_entry
end

function app_algorithm.apply(snapshot, runtime)
	local next_snapshot = clone_table(snapshot)
	local next_runtime = ensure_table(clone_table(runtime))
	local current_runtime
	local filtered_current

	next_runtime.temp_hum = ensure_table(next_runtime.temp_hum)

	if type(next_snapshot.temp_hum) == "table" then
		for index, entry in pairs(next_snapshot.temp_hum) do
			local next_entry
			local next_runtime_entry

			next_entry, next_runtime_entry = process_temp_hum_channel(entry, next_runtime.temp_hum[index])
			next_snapshot.temp_hum[index] = next_entry
			next_runtime.temp_hum[index] = next_runtime_entry
		end
	end

	if type(next_snapshot.current_sensor_mv) == "number" then
		current_runtime = ensure_table(next_runtime.current)
		current_runtime.window = append_window(current_runtime.window, next_snapshot.current_sensor_mv)
		filtered_current = average(current_runtime.window)
		if type(filtered_current) == "number" then
			next_snapshot.current_sensor_mv = filtered_current
		end
		next_runtime.current = current_runtime
	end

	return next_snapshot, next_runtime
end

return app_algorithm
