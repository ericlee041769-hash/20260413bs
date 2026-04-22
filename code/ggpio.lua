-- 板级 GPIO 统一封装。
-- 负责电源使能脚、门磁输入和 VBUS 检测，避免业务层直接操作裸 GPIO。
local io_ctrl = {}

io_ctrl.GPIO_ADC_EN = 24
io_ctrl.GPIO_3V3_EN = 25
io_ctrl.GPIO_5V_EN = 27
io_ctrl.GPIO_28 = 28
io_ctrl.GPIO21_VBUS = 21
io_ctrl.WAKEUP0_DOOR = gpio.WAKEUP0

local managed_pins = {
	-- 这里只收口“本工程主动输出控制”的 GPIO。
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
local vbus_input_reader = nil
local last_vbus_level = nil
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

local function level_text(level)
	if level == nil then
		return "未知"
	end

	if normalize_level(level) ~= 0 then
		return "高"
	end

	return "低"
end

local function read_vbus_level()
	if type(vbus_input_reader) ~= "function" then
		return nil
	end

	return normalize_level(vbus_input_reader())
end

local function is_valid_pin(pin)
	return managed_pin_set[pin] == true
end

local function wakeup0_callback(level, pin)
	-- 门磁边沿中断只做状态刷新和事件派发，业务判断在 application 中完成。
	door_open = door_state_from_level(level)
	log_info("ggpio", "门磁触发", pin, level, door_open and "打开" or "关闭")
	if sys and type(sys.publish) == "function" then
		sys.publish(DOOR_EDGE_EVENT, pin, level)
	end
end

local function setup_wakeup0()
	-- 门磁输入使用 WAKEUP0，既能做输入检测，也方便低功耗场景唤醒。
	local irq_mode = gpio.BOTH or gpio.FALLING

	door_input_reader = gpio.setup(io_ctrl.WAKEUP0_DOOR, wakeup0_callback, gpio.PULLUP, irq_mode)
	if type(door_input_reader) == "function" then
		door_open = door_state_from_level(door_input_reader())
	end
	log_info("ggpio", "门磁初始化", io_ctrl.WAKEUP0_DOOR, door_open and "打开" or "关闭")
end

local function setup_vbus_detect()
	-- GPIO21 作为 VBUS 检测输入；初始化时先记录一次原始电平，便于排查供电逻辑。
	local pulldown = gpio.PULLDOWN
	local initial_level

	vbus_input_reader = gpio.setup(io_ctrl.GPIO21_VBUS, nil, pulldown)
	initial_level = read_vbus_level()
	last_vbus_level = initial_level
	log_info("ggpio", "VBUS检测初始化", io_ctrl.GPIO21_VBUS, initial_level, level_text(initial_level))
end

function io_ctrl.init()
	-- 板级控制脚默认全部拉高使能，随后再初始化输入检测口。
	for i = 1, #managed_pins do
		local pin = managed_pins[i]
		gpio.setup(pin, 1)
		gpio.set(pin, 1)
		pin_levels[pin] = 1
	end
	setup_vbus_detect()
	setup_wakeup0()
	return true
end

function io_ctrl.set(pin, level)
	-- 所有输出脚统一走这里，便于后续加日志或防误操作保护。
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
	-- 每次读取都以当前引脚状态为准，避免只依赖中断回调里的缓存。
	if type(door_input_reader) == "function" then
		door_open = door_state_from_level(door_input_reader())
	end
	return door_open
end

function io_ctrl.get_usb_power_state()
	-- 额外返回原始 level，方便上层在日志里直接打印 GPIO21 电平。
	local level = read_vbus_level()

	if level == nil then
		return nil, nil
	end

	if last_vbus_level ~= level then
		last_vbus_level = level
		log_info("ggpio", "GPIO21状态变化", io_ctrl.GPIO21_VBUS, level, level_text(level))
	end

	return level ~= 0, level
end

return io_ctrl
