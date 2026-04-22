-- AirLBS 定位适配层。
-- 负责初始化请求参数、控制请求频率、缓存上一次有效定位，并兼容多种返回结构。
local glbs = {}

local DEFAULT_TIMEOUT = 10000
local REQUEST_INTERVAL_MS = 60000
local ZERO_LOCATION = { 0, 0 }

local is_inited = false
local request_cfg = nil
local last_request_ms = nil
local last_location = { 0, 0 }
local has_last_location = false

local function log_error(tag, ...)
	if log and log.error then
		log.error(tag, ...)
	end
end

local function log_warn(tag, ...)
	if log and type(log.warn) == "function" then
		log.warn(tag, ...)
		return
	end

	log_error(tag, ...)
end

local function log_info(tag, ...)
	if log and type(log.info) == "function" then
		log.info(tag, ...)
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

local function copy_location(source)
	return { source[1], source[2] }
end

local function reset_runtime_state()
	-- 重新初始化后必须清掉上一次定位缓存，避免旧配置污染新定位结果。
	last_request_ms = nil
	last_location = { 0, 0 }
	has_last_location = false
end

local function now_ms()
	return (os.time() or 0) * 1000
end

local function trim_str(value)
	if type(value) ~= "string" then
		return value
	end

	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_number(value)
	if type(value) == "number" then
		return value
	end

	if type(value) == "string" then
		return tonumber(trim_str(value))
	end
end

local function is_valid_lat_lng(lat, lng)
	return lat and lng
		and lat >= -90 and lat <= 90
		and lng >= -180 and lng <= 180
end

local function parse_location_pair(value)
	if type(value) ~= "string" then
		return nil, nil
	end

	local lon_str, lat_str = value:match("^%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
	local lon = tonumber(lon_str)
	local lat = tonumber(lat_str)
	if not lon or not lat then
		return nil, nil
	end

	return lat, lon
end

local function extract_airlbs_lat_lng(data)
	-- AirLBS 返回结构不稳定，这里尽量兼容不同字段名和嵌套层级。
	local lat
	local lng
	local location_fields
	local nested_fields

	if type(data) ~= "table" then
		return nil, nil
	end

	lat = normalize_number(data.lat) or normalize_number(data.latitude) or normalize_number(data.y)
	lng = normalize_number(data.lng) or normalize_number(data.lon) or normalize_number(data.longitude) or normalize_number(data.x)
	if is_valid_lat_lng(lat, lng) then
		return lat, lng
	end

	location_fields = {
		data.location,
		data.loc,
		data.position,
		data.coordinate
	}

	for i = 1, #location_fields do
		lat, lng = parse_location_pair(location_fields[i])
		if is_valid_lat_lng(lat, lng) then
			return lat, lng
		end
	end

	nested_fields = {
		data.result,
		data.data,
		data.location,
		data.loc,
		data.position,
		data.coordinate
	}

	for i = 1, #nested_fields do
		if type(nested_fields[i]) == "table" then
			lat, lng = extract_airlbs_lat_lng(nested_fields[i])
			if is_valid_lat_lng(lat, lng) then
				return lat, lng
			end
		end
	end

	for i = 1, #data do
		if type(data[i]) == "table" then
			lat, lng = extract_airlbs_lat_lng(data[i])
			if is_valid_lat_lng(lat, lng) then
				return lat, lng
			end
		elseif type(data[i]) == "string" then
			lat, lng = parse_location_pair(data[i])
			if is_valid_lat_lng(lat, lng) then
				return lat, lng
			end
		end
	end

	return nil, nil
end

local function wait_for_default_network(timeout_ms)
	-- 定位请求前等待默认网络 ready，避免请求直接在底层失败。
	local elapsed = 0

	if type(socket) ~= "table" or type(socket.adapter) ~= "function" or type(socket.dft) ~= "function" then
		return true
	end

	while not socket.adapter(socket.dft()) do
		if elapsed >= timeout_ms then
			return false, "network_not_ready"
		end

		log_warn("glbs.get_location", "等待IP_READY", socket.dft())
		if type(sys) ~= "table" or type(sys.waitUntil) ~= "function" then
			return false, "network_not_ready"
		end

		sys.waitUntil("IP_READY", 1000)
		elapsed = elapsed + 1000
	end

	return true
end

local function build_request_param()
	return {
		project_id = request_cfg.project_id,
		project_key = request_cfg.project_key,
		timeout = request_cfg.timeout,
		adapter = request_cfg.adapter,
		wifi_info = request_cfg.wifi_info
	}
end

local function request_due(current_ms)
	-- 通过最小请求间隔限制定位频率，避免过度请求。
	return last_request_ms == nil or (current_ms - last_request_ms) >= REQUEST_INTERVAL_MS
end

local function request_location(request_time_ms)
	-- 真正执行一次 AirLBS 请求，并把成功结果写入 last_location。
	local request_param
	local timeout_ms
	local ready
	local err
	local ok
	local data
	local lat
	local lng
	local airlbs_lib = airlbs

	if airlbs_lib == nil and type(require) == "function" then
		local require_ok, loaded = pcall(require, "airlbs")
		if require_ok then
			airlbs_lib = loaded
		end
	end

	if not airlbs_lib or type(airlbs_lib.request) ~= "function" then
		log_error("glbs.get_location", "airlbs.request unavailable")
		return false
	end

	timeout_ms = tonumber(request_cfg.timeout) or DEFAULT_TIMEOUT
	log_info(
		"glbs.get_location",
		"开始定位请求",
		request_cfg.project_id or "",
		type(request_cfg.project_key) == "string" and #request_cfg.project_key or 0,
		timeout_ms
	)
	ready, err = wait_for_default_network(timeout_ms)
	if not ready then
		log_error("glbs.get_location", "network not ready", err)
		return false
	end

	if type(socket) == "table" and type(socket.sntp) == "function" then
		socket.sntp()
		if type(sys) == "table" and type(sys.waitUntil) == "function" then
			sys.waitUntil("NTP_UPDATE", 1000)
		end
	end

	request_param = build_request_param()
	last_request_ms = request_time_ms
	ok, data = airlbs_lib.request(request_param)
	log_info("glbs.get_location", "airlbs.request result", ok, safe_json_encode(data))
	lat, lng = extract_airlbs_lat_lng(data)
	if ok and is_valid_lat_lng(lat, lng) then
		last_location = { lat, lng }
		has_last_location = true
		log_info("glbs.get_location", "定位成功", lat, lng)
		return true
	end

	log_error("glbs.get_location", "airlbs request failed", ok, safe_json_encode(data))
	return false
end

function glbs.init(cfg)
	-- project_id 为空时直接视为未初始化，业务层会自动回退到默认坐标。
	if type(cfg) ~= "table" or type(cfg.project_id) ~= "string" or cfg.project_id == "" then
		log_error("glbs.init", "project_id is required")
		is_inited = false
		request_cfg = nil
		reset_runtime_state()
		return false
	end

	request_cfg = {
		project_id = cfg.project_id,
		project_key = cfg.project_key,
		timeout = cfg.timeout or DEFAULT_TIMEOUT,
		adapter = cfg.adapter,
		wifi_info = cfg.wifi_info
	}
	is_inited = true
	reset_runtime_state()
	log_info(
		"glbs.init",
		"定位模块初始化",
		request_cfg.project_id or "",
		type(request_cfg.project_key) == "string" and #request_cfg.project_key or 0,
		request_cfg.timeout
	)
	return true
end

function glbs.is_ready()
	return is_inited
end

function glbs.get_location()
	-- 获取定位时优先走限频缓存；只有超过间隔才真的发起新请求。
	local current_ms

	if not is_inited then
		log_error("glbs.get_location", "module not initialized")
		return copy_location(ZERO_LOCATION)
	end

	current_ms = now_ms()
	if not request_due(current_ms) then
		log_info("glbs.get_location", "定位请求间隔未到，直接使用缓存", has_last_location)
		if has_last_location then
			return copy_location(last_location)
		end
		return copy_location(ZERO_LOCATION)
	end

	if request_location(current_ms) then
		return copy_location(last_location)
	end

	if has_last_location then
		return copy_location(last_location)
	end

	return copy_location(ZERO_LOCATION)
end

return glbs
