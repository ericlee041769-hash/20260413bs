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

local function log_info(tag, ...)
	if log and type(log.info) == "function" then
		log.info(tag, ...)
	end
end

local function copy_location(source)
	return { source[1], source[2] }
end

local function reset_runtime_state()
	last_request_ms = nil
	last_location = { 0, 0 }
	has_last_location = false
end

local function now_ms()
	return (os.time() or 0) * 1000
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
	return last_request_ms == nil or (current_ms - last_request_ms) >= REQUEST_INTERVAL_MS
end

local function request_location(request_time_ms)
	local ok
	local data

	if not airlbs or type(airlbs.request) ~= "function" then
		log_error("glbs.get_location", "airlbs.request unavailable")
		return false
	end

	last_request_ms = request_time_ms
	ok, data = airlbs.request(build_request_param())
	if ok and type(data) == "table" and type(data.lat) == "number" and type(data.lng) == "number" then
		last_location = { data.lat, data.lng }
		has_last_location = true
		log_info("glbs.get_location", "定位成功", data.lat, data.lng)
		return true
	end

	log_error("glbs.get_location", "airlbs request failed")
	return false
end

function glbs.init(cfg)
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
	return true
end

function glbs.is_ready()
	return is_inited
end

function glbs.get_location()
	local current_ms

	if not is_inited then
		log_error("glbs.get_location", "module not initialized")
		return copy_location(ZERO_LOCATION)
	end

	current_ms = now_ms()
	if not request_due(current_ms) then
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
