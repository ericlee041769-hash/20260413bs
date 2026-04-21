local app_config = {}

local CONFIG_KEY = "app:config"
local current_config = nil

local DEFAULT_CONFIG = {
	sample_interval_ms = 10000,
	report_interval_ms = 10000,
	airlbs_project_id = "",
	airlbs_project_key = "",
	airlbs_timeout = 10000,
	temp_low = -40,
	temp_high = 85,
	current_low = 0,
	current_high = 50000,
	pressure_diff_low = 1.0,
	pressure_diff_high = 1.5,
	door_open_warn_ms = 5000
}

local FIELD_TYPES = {
	sample_interval_ms = "number",
	report_interval_ms = "number",
	airlbs_project_id = "string",
	airlbs_project_key = "string",
	airlbs_timeout = "number",
	temp_low = "number",
	temp_high = "number",
	current_low = "number",
	current_high = "number",
	pressure_diff_low = "number",
	pressure_diff_high = "number",
	door_open_warn_ms = "number"
}

local function clone_table(source)
	local target = {}

	for key, value in pairs(source) do
		target[key] = value
	end

	return target
end

local function merge_tables(base, overlay)
	local merged = clone_table(base)

	if type(overlay) ~= "table" then
		return merged
	end

	for key, value in pairs(overlay) do
		merged[key] = value
	end

	return merged
end

local function load_persisted()
	if not fskv or type(fskv.get) ~= "function" then
		return nil
	end

	return fskv.get(CONFIG_KEY)
end

local function save_persisted(cfg)
	if fskv and type(fskv.set) == "function" then
		fskv.set(CONFIG_KEY, cfg)
	end
end

function app_config.load()
	local persisted = load_persisted()

	current_config = merge_tables(DEFAULT_CONFIG, persisted)
	save_persisted(current_config)
	return clone_table(current_config)
end

function app_config.get()
	if current_config == nil then
		return app_config.load()
	end

	return clone_table(current_config)
end

function app_config.update(changes)
	local next_config = app_config.get()
	local applied = {}

	if type(changes) ~= "table" then
		return applied
	end

	for key, value in pairs(changes) do
		if FIELD_TYPES[key] ~= nil and type(value) == FIELD_TYPES[key] then
			next_config[key] = value
			applied[key] = value
		end
	end

	current_config = next_config
	save_persisted(current_config)
	return clone_table(applied)
end

return app_config
