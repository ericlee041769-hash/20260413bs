local gsht30 = {}

gsht30.I2C0 = 0
gsht30.I2C1 = 1
gsht30.DEFAULT_ADDR = 0x44
gsht30.ALT_ADDR = 0x45

local managed_buses = {
	gsht30.I2C0,
	gsht30.I2C1
}

local function is_valid_bus(id)
	return id == gsht30.I2C0 or id == gsht30.I2C1
end

function gsht30.init(speed)
	local bus_speed = speed or i2c.FAST

	for i = 1, #managed_buses do
		local id = managed_buses[i]
		if not i2c.exist(id) then
			if log and log.error then
				log.error("gsht30.init", "i2c not exist", id)
			end
			return false
		end
	end

	for i = 1, #managed_buses do
		local id = managed_buses[i]
		if i2c.setup(id, bus_speed) ~= 1 then
			if log and log.error then
				log.error("gsht30.init", "i2c setup failed", id, bus_speed)
			end
			return false
		end
	end

	return true
end

function gsht30.read(id, addr)
	local device_addr = addr or gsht30.DEFAULT_ADDR
	local ok
	local humidity
	local temperature

	if not is_valid_bus(id) then
		if log and log.error then
			log.error("gsht30.read", "invalid i2c id", id)
		end
		return false, nil, nil
	end

	ok, humidity, temperature = i2c.readSHT30(id, device_addr)
	if ok or addr ~= nil then
		return ok, humidity, temperature
	end

	return i2c.readSHT30(id, gsht30.ALT_ADDR)
end

function gsht30.read_all(addr)
	local result = {}
	local ids = managed_buses

	for i = 1, #ids do
		local id = ids[i]
		local ok, humidity, temperature = gsht30.read(id, addr)
		result[id] = {
			ok = ok,
			humidity = humidity,
			temperature = temperature
		}
	end

	return result
end

return gsht30
