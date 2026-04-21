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
	current_config = merge_tables(app_config.get(), changes)
	save_persisted(current_config)
	return clone_table(current_config)
end

return app_config
