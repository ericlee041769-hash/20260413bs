local io_ctrl = {}

io_ctrl.GPIO_ADC_EN = 24
io_ctrl.GPIO_3V3_EN = 25
io_ctrl.GPIO_5V_EN = 27
io_ctrl.GPIO_28 = 28
io_ctrl.WAKEUP0_DOOR = gpio.WAKEUP0

local managed_pins = {
	io_ctrl.GPIO_ADC_EN,
	io_ctrl.GPIO_3V3_EN,
	io_ctrl.GPIO_5V_EN,
	io_ctrl.GPIO_28
}

local managed_pin_set = {
	[io_ctrl.GPIO_ADC_EN] = true,
	[io_ctrl.GPIO_3V3_EN] = true,
	[io_ctrl.GPIO_5V_EN] = true,
	[io_ctrl.GPIO_28] = true
}

local pin_levels = {}
local door_open = false
local door_input_reader = nil
local DOOR_EDGE_EVENT = "APP_DOOR_EDGE"

local function normalize_level(level)
	if level == false or level == 0 then
		return 0
	end
	return 1
end

local function log_info(...)
	if log and type(log.info) == "function" then
		log.info(...)
	end
end

local function door_state_from_level(level)
	return normalize_level(level) ~= 0
end

local function is_valid_pin(pin)
	return managed_pin_set[pin] == true
end

local function wakeup0_callback(level, pin)
	door_open = door_state_from_level(level)
	log_info("ggpio", "门磁触发", pin, level, door_open and "打开" or "关闭")
	if sys and type(sys.publish) == "function" then
		sys.publish(DOOR_EDGE_EVENT, pin, level)
	end
end

local function setup_wakeup0()
	local irq_mode = gpio.BOTH or gpio.FALLING

	door_input_reader = gpio.setup(io_ctrl.WAKEUP0_DOOR, wakeup0_callback, gpio.PULLUP, irq_mode)
	if type(door_input_reader) == "function" then
		door_open = door_state_from_level(door_input_reader())
	end
	log_info("ggpio", "门磁初始化", io_ctrl.WAKEUP0_DOOR, door_open and "打开" or "关闭")
end

function io_ctrl.init()
	for i = 1, #managed_pins do
		local pin = managed_pins[i]
		gpio.setup(pin, 1)
		gpio.set(pin, 1)
		pin_levels[pin] = 1
	end
	setup_wakeup0()
	return true
end

function io_ctrl.set(pin, level)
	local normalized_level
	local previous_level

	if not is_valid_pin(pin) then
		if log and log.error then
			log.error("io.set", "invalid pin", pin)
		end
		return false
	end

	normalized_level = normalize_level(level)
	previous_level = pin_levels[pin]
	gpio.set(pin, normalized_level)
	pin_levels[pin] = normalized_level

	if previous_level ~= nil and previous_level ~= normalized_level and log and log.info then
		log.info("ggpio", "level changed", pin, previous_level, normalized_level)
	end

	return true
end

function io_ctrl.set_3v3(level)
	return io_ctrl.set(io_ctrl.GPIO_3V3_EN, level)
end

function io_ctrl.set_5v(level)
	return io_ctrl.set(io_ctrl.GPIO_5V_EN, level)
end

function io_ctrl.set_adc(level)
	return io_ctrl.set(io_ctrl.GPIO_ADC_EN, level)
end

function io_ctrl.set_gpio28(level)
	return io_ctrl.set(io_ctrl.GPIO_28, level)
end

function io_ctrl.get_door_state()
	if type(door_input_reader) == "function" then
		door_open = door_state_from_level(door_input_reader())
	end
	return door_open
end

return io_ctrl
