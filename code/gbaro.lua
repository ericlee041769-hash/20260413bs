-- 串口压差/气压传感器驱动。
-- 当前协议是私有帧格式：先发命令，再读回带 CRC 的应答帧。
local gbaro = {}

gbaro.UART1 = 1
gbaro.UART2 = 2
gbaro.BAUD_RATE = 9600
gbaro.CMD_CAL_T = 0x0E
gbaro.CMD_CAL_P1 = 0x0D

local REQUEST_START = 0x55
local RESPONSE_START = 0xAA
local REQUEST_LENGTH = 0x04
local RESPONSE_TYPE_T = 0x0A
local RESPONSE_TYPE_P1 = 0x09
local DEFAULT_DATA_BITS = 8
local DEFAULT_STOP_BITS = 1
local DEFAULT_BUFFER_SIZE = 1024
local DEFAULT_TIMEOUT_MS = 200
local POLL_INTERVAL_MS = 10
local READ_SIZE = 1024

local managed_uarts = {
	gbaro.UART1,
	gbaro.UART2
}

local function is_valid_uart(id)
	return id == gbaro.UART1 or id == gbaro.UART2
end

local function log_error(tag, ...)
	if log and log.error then
		log.error(tag, ...)
	end
end

local function crc8_maxim(data)
	-- 设备协议使用 CRC-8/MAXIM，发包和收包校验都复用这一份实现。
	local crc = 0

	for i = 1, #data do
		crc = (crc ~ string.byte(data, i)) & 0xFF
		for _ = 1, 8 do
			if (crc & 0x01) ~= 0 then
				crc = ((crc >> 1) ~ 0x8C) & 0xFF
			else
				crc = (crc >> 1) & 0xFF
			end
		end
	end

	return crc
end

local function build_request(cmd)
	local payload = string.char(REQUEST_START, REQUEST_LENGTH, cmd)
	local crc = crc8_maxim(payload)

	return payload .. string.char(crc)
end

local function read_frame(id, timeout_ms)
	-- 按长度字段拼完整帧；一旦帧头错误就直接返回，避免误吞数据。
	local frame = ""
	local waited_ms = 0

	while waited_ms <= timeout_ms do
		local chunk = uart.read(id, READ_SIZE) or ""
		if #chunk > 0 then
			frame = frame .. chunk

			if string.byte(frame, 1) ~= RESPONSE_START then
				return false, { error = "invalid frame header" }
			end

			if #frame >= 2 then
				local frame_length = string.byte(frame, 2)
				if frame_length < 4 then
					return false, { error = "invalid frame length" }
				end

				if #frame >= frame_length then
					return true, string.sub(frame, 1, frame_length)
				end
			end
		end

		if waited_ms >= timeout_ms then
			break
		end

		sys.wait(POLL_INTERVAL_MS)
		waited_ms = waited_ms + POLL_INTERVAL_MS
	end

	return false, { error = "uart response timeout" }
end

local function validate_frame(frame)
	-- 收到完整帧后再次校验头、长度和 CRC，避免上层解析脏数据。
	local frame_length
	local expected_crc
	local actual_crc

	if type(frame) ~= "string" or #frame < 4 then
		return false, { error = "invalid frame length" }
	end

	if string.byte(frame, 1) ~= RESPONSE_START then
		return false, { error = "invalid frame header" }
	end

	frame_length = string.byte(frame, 2)
	if frame_length ~= #frame or frame_length < 4 then
		return false, { error = "invalid frame length" }
	end

	expected_crc = crc8_maxim(string.sub(frame, 1, -2))
	actual_crc = string.byte(frame, -1)
	if expected_crc ~= actual_crc then
		return false, { error = "crc mismatch" }
	end

	return true, string.byte(frame, 3), string.sub(frame, 4, -2)
end

local function decode_s16_le(payload)
	local value = string.byte(payload, 1) | (string.byte(payload, 2) << 8)

	if value >= 0x8000 then
		value = value - 0x10000
	end

	return value
end

local function decode_u32_le(payload)
	return string.byte(payload, 1)
		| (string.byte(payload, 2) << 8)
		| (string.byte(payload, 3) << 16)
		| (string.byte(payload, 4) << 24)
end

local function parse_temperature_frame(frame)
	-- 温度帧返回有符号 16 位整数，单位是 0.1 摄氏度。
	local ok
	local data_type
	local payload
	local raw_value

	ok, data_type, payload = validate_frame(frame)
	if not ok then
		return false, data_type
	end

	if data_type ~= RESPONSE_TYPE_T then
		return false, { error = "unexpected frame type" }
	end

	if #payload ~= 2 then
		return false, { error = "invalid temperature payload" }
	end

	raw_value = decode_s16_le(payload)
	return true, {
		temperature_raw = raw_value,
		temperature = raw_value / 10
	}
end

local function parse_pressure_frame(frame)
	-- 压力帧返回无符号 32 位整数，当前换算成 kPa。
	local ok
	local data_type
	local payload
	local raw_value

	ok, data_type, payload = validate_frame(frame)
	if not ok then
		return false, data_type
	end

	if data_type ~= RESPONSE_TYPE_P1 then
		return false, { error = "unexpected frame type" }
	end

	if #payload ~= 4 then
		return false, { error = "invalid pressure payload" }
	end

	raw_value = decode_u32_le(payload)
	return true, {
		pressure_raw = raw_value,
		pressure = raw_value / 1000
	}
end

local function read_command(id, cmd, timeout_ms)
	-- 每次发送新命令前先清空接收缓冲，避免把上一帧残留拼进来。
	local request = build_request(cmd)
	local written

	uart.rxClear(id)
	written = uart.write(id, request)
	if type(written) ~= "number" or written < #request then
		return false, { error = "uart write failed" }
	end

	return read_frame(id, timeout_ms)
end

local function read_temperature(id, timeout_ms)
	local ok
	local frame_or_err

	ok, frame_or_err = read_command(id, gbaro.CMD_CAL_T, timeout_ms)
	if not ok then
		return false, frame_or_err
	end

	return parse_temperature_frame(frame_or_err)
end

local function read_pressure(id, timeout_ms)
	local ok
	local frame_or_err

	ok, frame_or_err = read_command(id, gbaro.CMD_CAL_P1, timeout_ms)
	if not ok then
		return false, frame_or_err
	end

	return parse_pressure_frame(frame_or_err)
end

function gbaro.init()
	-- 两路串口都按统一参数初始化，任一路失败都视为模块初始化失败。
	local uart_none = uart.None or uart.NONE

	for i = 1, #managed_uarts do
		local id = managed_uarts[i]
		local result = uart.setup(id, gbaro.BAUD_RATE, DEFAULT_DATA_BITS, DEFAULT_STOP_BITS, uart_none, uart.LSB, DEFAULT_BUFFER_SIZE)
		if result ~= 0 then
			log_error("gbaro.init", "uart setup failed", id, result)
			return false
		end
	end

	return true
end

function gbaro.read(id, timeout_ms)
	-- 单路读取需要先拿温度，再拿压力；任一步失败都会返回错误结构。
	local read_timeout_ms = timeout_ms or DEFAULT_TIMEOUT_MS
	local temp_ok
	local temp_result
	local pressure_ok
	local pressure_result

	if not is_valid_uart(id) then
		return false, { error = "invalid uart id" }
	end

	temp_ok, temp_result = read_temperature(id, read_timeout_ms)
	if not temp_ok then
		log_error("gbaro.read", "temperature read failed", id, temp_result.error)
		return false, temp_result
	end

	pressure_ok, pressure_result = read_pressure(id, read_timeout_ms)
	if not pressure_ok then
		log_error("gbaro.read", "pressure read failed", id, pressure_result.error)
		return false, pressure_result
	end

	return true, {
		temperature_raw = temp_result.temperature_raw,
		temperature = temp_result.temperature,
		pressure_raw = pressure_result.pressure_raw,
		pressure = pressure_result.pressure
	}
end

function gbaro.read_all(timeout_ms)
	-- 对上层统一返回 { [uart_id] = { ok = ..., ... } } 结构，便于直接聚合。
	local result = {}

	for i = 1, #managed_uarts do
		local id = managed_uarts[i]
		local ok
		local reading

		ok, reading = gbaro.read(id, timeout_ms)
		if ok then
			result[id] = {
				ok = true,
				temperature_raw = reading.temperature_raw,
				temperature = reading.temperature,
				pressure_raw = reading.pressure_raw,
				pressure = reading.pressure
			}
		else
			result[id] = {
				ok = false,
				error = reading.error
			}
		end
	end

	return result
end

return gbaro
