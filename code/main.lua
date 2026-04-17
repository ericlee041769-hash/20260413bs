PROJECT = "Air780EPM"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.config = require("config")
_G.application = require("application")
_G.ggpio = require("ggpio")
_G.gadc = require("gadc")
_G.gsht30 = require("gsht30")
_G.gmqtt = require("gmqtt")

local device_props = {
	sn = "AIR780EPM-SN-001",
	model = "Air780EPM",
	color = "red",
	temp = 25.0,
	fanSpeed = 1.0,
	door = false,
	humidity = 50.0,
	err = false,
	time = os.date("%Y-%m-%d %H:%M:%S")
}
ggpio.init()

gmqtt.start(device_props)

sys.taskInit(function()
	log.info("main", "start gadc test loop")

	while true do
		local battery_mv, battery_percent = gadc.read_battery()
		local raw_value, adc_mv, sensor_mv = gadc.read_wcs1500_adc0()
		local battery_mv_desc = battery_mv and (tostring(battery_mv) .. "mV") or "读取失败"
		local battery_percent_desc = battery_percent and (tostring(battery_percent) .. "%") or "读取失败"
		local raw_value_desc = raw_value and tostring(raw_value) or "读取失败"
		local adc_mv_desc = adc_mv and (tostring(adc_mv) .. "mV") or "读取失败"
		local sensor_mv_desc = sensor_mv and (tostring(sensor_mv) .. "mV") or "读取失败"

		log.info("main", "gadc测试", "电池电压", battery_mv_desc, "电池电量", battery_percent_desc, "ADC原始值", raw_value_desc, "ADC电压", adc_mv_desc, "传感器电压", sensor_mv_desc)
		sys.wait(1000)
	end
end)

sys.taskInit(function()
	log.info("main", "start gsht30 test loop")

	if not gsht30.init() then
		log.error("main", "gsht30初始化失败")
		return
	end

	while true do
		local all = gsht30.read_all()
		local i2c0 = all[gsht30.I2C0] or {}
		local i2c1 = all[gsht30.I2C1] or {}
		local i2c0_hum = i2c0.humidity and (tostring(i2c0.humidity) .. "%") or "读取失败"
		local i2c0_temp = i2c0.temperature and (tostring(i2c0.temperature) .. "C") or "读取失败"
		local i2c1_hum = i2c1.humidity and (tostring(i2c1.humidity) .. "%") or "读取失败"
		local i2c1_temp = i2c1.temperature and (tostring(i2c1.temperature) .. "C") or "读取失败"

		log.info("main", "gsht30测试", "I2C0状态", tostring(i2c0.ok), "I2C0湿度", i2c0_hum, "I2C0温度", i2c0_temp, "I2C1状态", tostring(i2c1.ok), "I2C1湿度", i2c1_hum, "I2C1温度", i2c1_temp)
		sys.wait(1000)
	end
end)

-- gpio.setup(23,1)
-- gpio.set(23,1)

-- local function apply_gpio_test_level(level)
-- 	ggpio.set_adc(level)
-- 	ggpio.set_3v3(level)
-- 	ggpio.set_5v(level)
-- 	ggpio.set_gpio28(level)
-- end

-- sys.taskInit(function()
-- 	local level = false

-- 	log.info("main", "start gpio toggle test")
-- 	ggpio.init()

-- 	while true do
-- 		apply_gpio_test_level(level)
-- 		level = not level
-- 		sys.wait(10000)
-- 	end
-- end)

sys.run()
