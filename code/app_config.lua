-- 运行配置管理。
-- 负责把默认配置、持久化配置和云端下发配置合并成一份当前有效配置。
local app_config = {}
local config = require("config")

local CONFIG_KEY = "app:config"
local current_config = nil

local DEFAULT_CONFIG = config.RUNTIME_DEFAULTS or {}
local FIELD_TYPES = config.RUNTIME_FIELD_TYPES or {}
local MUTABLE_FIELDS = config.RUNTIME_MUTABLE_FIELDS or {}

local function log_info(...)
	if log and type(log.info) == "function" then
		log.info(...)
	end
end

local function log_warn(...)
	if log and type(log.warn) == "function" then
		log.warn(...)
	end
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

local function load_persisted()
	-- fskv 不可用时允许系统以默认配置继续运行。
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

local function key_length(value)
	if type(value) == "string" then
		return #value
	end

	return 0
end

local function max_number(...)
	local result = nil
	local values = { ... }

	for i = 1, #values do
		if type(values[i]) == "number" then
			if result == nil or values[i] > result then
				result = values[i]
			end
		end
	end

	return result
end

local function merge_known_fields(base, overlay)
	-- 只接受默认配置中已经声明过的键，避免脏数据进入运行时配置。
	local merged = clone_table(base)

	if type(overlay) ~= "table" then
		return merged
	end

	for key, _ in pairs(base) do
		if overlay[key] ~= nil then
			merged[key] = overlay[key]
		end
	end

	return merged
end

local function migrate_legacy_intervals(persisted)
	-- 兼容历史 sample/report 字段，统一迁移成现在的 usb_interval_ms / battery_interval_ms。
	local migrated = clone_table(persisted)
	local usb_interval
	local battery_interval

	if type(persisted) ~= "table" then
		return migrated
	end

	usb_interval = max_number(
		persisted.usb_interval_ms,
		persisted.usb_sample_interval_ms,
		persisted.usb_report_interval_ms,
		persisted.sample_interval_ms,
		persisted.report_interval_ms
	)
	if usb_interval ~= nil then
		migrated.usb_interval_ms = usb_interval
	end

	battery_interval = max_number(
		persisted.battery_interval_ms,
		persisted.battery_sample_interval_ms,
		persisted.battery_report_interval_ms,
		persisted.sample_interval_ms,
		persisted.report_interval_ms
	)
	if battery_interval ~= nil then
		migrated.battery_interval_ms = battery_interval
	end

	if usb_interval ~= nil or battery_interval ~= nil then
		log_info("app_config", "migrate legacy intervals", usb_interval, battery_interval)
	end

	return migrated
end

local function maybe_warn_airlbs_override(persisted, effective)
	if type(DEFAULT_CONFIG.airlbs_project_id) ~= "string" or DEFAULT_CONFIG.airlbs_project_id == "" then
		return
	end

	if type(persisted) ~= "table" then
		return
	end

	if persisted.airlbs_project_id == "" and effective.airlbs_project_id == "" then
		log_warn("app_config", "persisted airlbs config overrides defaults with blank values")
	end
end

function app_config.load()
	-- 启动时读取一次，并将迁移后的结果回写到 fskv，保持后续结构一致。
	local persisted = load_persisted()
	local migrated = migrate_legacy_intervals(persisted)

	current_config = merge_known_fields(DEFAULT_CONFIG, migrated)
	log_info(
		"app_config",
		"load config",
		persisted and persisted.airlbs_project_id or nil,
		DEFAULT_CONFIG.airlbs_project_id,
		current_config.airlbs_project_id,
		key_length(current_config.airlbs_project_key),
		current_config.airlbs_timeout
	)
	maybe_warn_airlbs_override(persisted, current_config)
	save_persisted(current_config)
	return clone_table(current_config)
end

function app_config.get()
	-- 对外返回副本，避免调用方误改共享状态。
	if current_config == nil then
		return app_config.load()
	end

	return clone_table(current_config)
end

function app_config.update(changes)
	-- 运行时只允许更新白名单字段，且必须满足声明的类型。
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
