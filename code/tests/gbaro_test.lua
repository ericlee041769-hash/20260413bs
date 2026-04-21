local calls = {}
local errors = {}
local wait_calls = {}

local function append_bytes(...)
	local bytes = { ... }
	local chars = {}

	for i = 1, #bytes do
		chars[i] = string.char(bytes[i])
	end

	return table.concat(chars)
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message .. ": expected true, got " .. tostring(value))
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message .. ": expected false, got " .. tostring(value))
	end
end

local function assert_table(value, message)
	if type(value) ~= "table" then
		error(message .. ": expected table, got " .. tostring(type(value)))
	end
end

_G.log = {
	error = function(...)
		errors[#errors + 1] = { ... }
	end
}

_G.sys = {
	wait = function(ms)
		wait_calls[#wait_calls + 1] = ms
	end
}

_G.uart = {
	None = 0,
	LSB = 0,
	_setup_result = {
		[1] = 0,
		[2] = 0
	},
	_write_result = {},
	_read_queue = {
		[1] = {},
		[2] = {}
	},
	setup = function(id, baud_rate, data_bits, stop_bits, parity, bit_order, buff_size)
		calls[#calls + 1] = {
			fn = "setup",
			id = id,
			baud_rate = baud_rate,
			data_bits = data_bits,
			stop_bits = stop_bits,
			parity = parity,
			bit_order = bit_order,
			buff_size = buff_size
		}
		return uart._setup_result[id] or -1
	end,
	rxClear = function(id)
		calls[#calls + 1] = { fn = "rxClear", id = id }
	end,
	write = function(id, data)
		calls[#calls + 1] = { fn = "write", id = id, data = data }
		if uart._write_result[id] ~= nil then
			return uart._write_result[id]
		end
		return #data
	end,
	read = function(id, len)
		local queue = uart._read_queue[id] or {}
		local data = queue[1] or ""
		calls[#calls + 1] = { fn = "read", id = id, len = len, data = data }
		if #queue > 0 then
			table.remove(queue, 1)
			uart._read_queue[id] = queue
		end
		return data
	end
}

local function clear_records()
	calls = {}
	errors = {}
	wait_calls = {}
	uart._setup_result[1] = 0
	uart._setup_result[2] = 0
	uart._write_result[1] = nil
	uart._write_result[2] = nil
	uart._read_queue[1] = {}
	uart._read_queue[2] = {}
end

local function set_read_queue(id, items)
	uart._read_queue[id] = {}
	for i = 1, #items do
		uart._read_queue[id][i] = items[i]
	end
end

local function find_nth_call(fn_name, n)
	local count = 0

	for i = 1, #calls do
		local call = calls[i]
		if call.fn == fn_name then
			count = count + 1
			if count == n then
				return call
			end
		end
	end

	return nil
end

local module_loader, load_err = loadfile("gbaro.lua")
assert(module_loader, load_err)
local gbaro = module_loader()

assert_equal(gbaro.UART1, 1, "UART1 constant")
assert_equal(gbaro.UART2, 2, "UART2 constant")
assert_equal(gbaro.BAUD_RATE, 9600, "BAUD_RATE constant")
assert_equal(gbaro.CMD_CAL_T, 0x0E, "CMD_CAL_T constant")
assert_equal(gbaro.CMD_CAL_P1, 0x0D, "CMD_CAL_P1 constant")

clear_records()
assert_true(gbaro.init(), "init return")
assert_equal(#calls, 2, "init call count")
assert_equal(calls[1].fn, "setup", "init first fn")
assert_equal(calls[1].id, gbaro.UART1, "init first id")
assert_equal(calls[1].baud_rate, 9600, "init first baud")
assert_equal(calls[1].data_bits, 8, "init first data bits")
assert_equal(calls[1].stop_bits, 1, "init first stop bits")
assert_equal(calls[1].parity, uart.None, "init first parity")
assert_equal(calls[1].bit_order, uart.LSB, "init first bit order")
assert_equal(calls[1].buff_size, 1024, "init first buff size")
assert_equal(calls[2].fn, "setup", "init second fn")
assert_equal(calls[2].id, gbaro.UART2, "init second id")

clear_records()
uart._setup_result[2] = -1
assert_false(gbaro.init(), "init fail return")
assert_equal(#errors, 1, "init fail log count")

clear_records()
set_read_queue(gbaro.UART1, {
	append_bytes(0xAA, 0x06, 0x0A, 0x02, 0x01, 0x22),
	append_bytes(0xAA, 0x08, 0x09, 0xA0, 0x86, 0x01, 0x00, 0x7F)
})
local ok, reading = gbaro.read(gbaro.UART1)
assert_true(ok, "read success return")
assert_table(reading, "read success result")
assert_equal(reading.temperature_raw, 258, "read temperature raw")
assert_equal(reading.temperature, 25.8, "read temperature")
assert_equal(reading.pressure_raw, 100000, "read pressure raw")
assert_equal(reading.pressure, 100.0, "read pressure")
assert_equal(find_nth_call("write", 1).data, append_bytes(0x55, 0x04, 0x0E, 0x6A), "temperature request frame")
assert_equal(find_nth_call("write", 2).data, append_bytes(0x55, 0x04, 0x0D, 0x88), "pressure request frame")

clear_records()
local invalid_ok, invalid_result = gbaro.read(3)
assert_false(invalid_ok, "invalid uart id return")
assert_table(invalid_result, "invalid uart id result")
assert_equal(invalid_result.error, "invalid uart id", "invalid uart id error")
assert_equal(#calls, 0, "invalid uart id call count")

clear_records()
local timeout_ok, timeout_result = gbaro.read(gbaro.UART1)
assert_false(timeout_ok, "timeout return")
assert_equal(timeout_result.error, "uart response timeout", "timeout error")
assert_true(#wait_calls > 0, "timeout should wait")

clear_records()
set_read_queue(gbaro.UART1, {
	append_bytes(0xAB, 0x06, 0x0A, 0x02, 0x01, 0x22)
})
local bad_header_ok, bad_header_result = gbaro.read(gbaro.UART1)
assert_false(bad_header_ok, "bad header return")
assert_equal(bad_header_result.error, "invalid frame header", "bad header error")

clear_records()
set_read_queue(gbaro.UART1, {
	append_bytes(0xAA, 0x06, 0x0A, 0x02, 0x01, 0x23)
})
local crc_ok, crc_result = gbaro.read(gbaro.UART1)
assert_false(crc_ok, "crc mismatch return")
assert_equal(crc_result.error, "crc mismatch", "crc mismatch error")

clear_records()
set_read_queue(gbaro.UART1, {
	append_bytes(0xAA, 0x06, 0x09, 0x02, 0x01, 0xC6)
})
local type_ok, type_result = gbaro.read(gbaro.UART1)
assert_false(type_ok, "unexpected type return")
assert_equal(type_result.error, "unexpected frame type", "unexpected type error")

clear_records()
set_read_queue(gbaro.UART1, {
	append_bytes(0xAA, 0x06, 0x0A, 0x02, 0x01, 0x22),
	append_bytes(0xAA, 0x08, 0x09, 0xA0, 0x86, 0x01, 0x00, 0x7F)
})
set_read_queue(gbaro.UART2, {
	append_bytes(0xAA, 0x06, 0x0A, 0x00, 0x00, 0xED),
	append_bytes(0xAA, 0x08, 0x09, 0x50, 0xC3, 0x00, 0x00, 0xCE)
})
local all = gbaro.read_all()
assert_true(all[gbaro.UART1].ok, "read_all uart1 ok")
assert_equal(all[gbaro.UART1].temperature, 25.8, "read_all uart1 temperature")
assert_equal(all[gbaro.UART1].pressure, 100.0, "read_all uart1 pressure")
assert_true(all[gbaro.UART2].ok, "read_all uart2 ok")
assert_equal(all[gbaro.UART2].temperature, 0.0, "read_all uart2 temperature")
assert_equal(all[gbaro.UART2].pressure, 50.0, "read_all uart2 pressure")
assert_equal(find_nth_call("write", 1).id, gbaro.UART1, "read_all first write id")
assert_equal(find_nth_call("write", 3).id, gbaro.UART2, "read_all third write id")

print("gbaro_test.lua: PASS")
