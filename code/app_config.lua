local app_config = {}
local config = require("config")

local CONFIG_KEY = "app:config"
local current_config = nil

local DEFAULT_CONFIG = config.RUNTIME_DEFAULTS or {}
local FIELD_TYPES = config.RUNTIME_FIELD_TYPES or {}
local MUTABLE_FIELDS = config.RUNTIME_MUTABLE_FIELDS or {}

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
		if MUTABLE_FIELDS[key] == true and FIELD_TYPES[key] ~= nil and type(value) == FIELD_TYPES[key] then
			next_config[key] = value
			applied[key] = value
		end
	end

	current_config = next_config
	save_persisted(current_config)
	return clone_table(applied)
end

return app_config
