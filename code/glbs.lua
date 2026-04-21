local glbs = {}

local DEFAULT_TIMEOUT = 10000
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

local function copy_location(source)
	return { source[1], source[2] }
end

local function reset_runtime_state()
	last_request_ms = nil
	last_location = { 0, 0 }
	has_last_location = false
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

function glbs.get_location()
	if not is_inited then
		log_error("glbs.get_location", "module not initialized")
		return copy_location(ZERO_LOCATION)
	end

	if has_last_location then
		return copy_location(last_location)
	end

	return copy_location(ZERO_LOCATION)
end

return glbs
