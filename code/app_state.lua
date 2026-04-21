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
	latest_snapshot = clone_table(snapshot)

	if fskv and type(fskv.set) == "function" then
		fskv.set(LATEST_KEY, latest_snapshot)
	end

	return clone_table(latest_snapshot)
end

function app_state.get_latest()
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
