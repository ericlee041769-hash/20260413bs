-- 最新快照状态缓存。
-- 这个模块只存一份“最后一次业务快照”，用于断电恢复和云端查询。
local app_state = {}

local LATEST_KEY = "app:latest"
local latest_snapshot = nil

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

function app_state.save_latest(snapshot)
	-- 保存时写内存和 fskv，两边保持一致。
	latest_snapshot = clone_table(snapshot)

	if fskv and type(fskv.set) == "function" then
		fskv.set(LATEST_KEY, latest_snapshot)
	end

	return clone_table(latest_snapshot)
end

function app_state.get_latest()
	-- 首次读取时如果内存没有，再尝试从 fskv 恢复。
	if latest_snapshot ~= nil then
		return clone_table(latest_snapshot)
	end

	if fskv and type(fskv.get) == "function" then
		local persisted = fskv.get(LATEST_KEY)
		if type(persisted) == "table" then
			latest_snapshot = clone_table(persisted)
		end
	end

	if latest_snapshot == nil then
		return nil
	end

	return clone_table(latest_snapshot)
end

return app_state
