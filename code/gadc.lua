-- ADC 采集封装。
-- 包含电池电压读取和 WCS1500 电流采样读取。
local gadc = {}

gadc.ADC0 = 0
gadc.BATTERY_EMPTY_MV = 3300
gadc.BATTERY_FULL_MV = 4200
gadc.WCS1500_DIVIDER_RATIO = 2

function gadc.battery_percent_from_mv(voltage_mv)
	-- 当前采用简单线性映射，适合粗略电量展示，不适合精确 SOC 估算。
	if type(voltage_mv) ~= "number" then
		return nil
	end

	if voltage_mv <= gadc.BATTERY_EMPTY_MV then
		return 0
	end

	if voltage_mv >= gadc.BATTERY_FULL_MV then
		return 100
	end

	return math.floor((voltage_mv - gadc.BATTERY_EMPTY_MV) * 100 / (gadc.BATTERY_FULL_MV - gadc.BATTERY_EMPTY_MV) + 0.5)
end

function gadc.read_battery()
	-- 使用 LuatOS 提供的 CH_VBAT 读取板载电池电压。
	local voltage_mv

	if not adc.open(adc.CH_VBAT) then
		if log and log.error then
			log.error("gadc.read_battery", "adc.open failed", adc.CH_VBAT)
		end
		return nil, nil
	end

	voltage_mv = adc.get(adc.CH_VBAT)
	adc.close(adc.CH_VBAT)

	if type(voltage_mv) ~= "number" or voltage_mv < 0 then
		if log and log.error then
			log.error("gadc.read_battery", "adc.get invalid", voltage_mv)
		end
		return nil, nil
	end

	return voltage_mv, gadc.battery_percent_from_mv(voltage_mv)
end

function gadc.read_wcs1500_adc0()
	-- 电流传感器输出经过分压，因此这里返回原始毫伏值和换算后的传感器毫伏值。
	local raw_value
	local adc_mv

	adc.setRange(adc.ADC_RANGE_MIN)

	if not adc.open(gadc.ADC0) then
		if log and log.error then
			log.error("gadc.read_wcs1500_adc0", "adc.open failed", gadc.ADC0)
		end
		return nil, nil, nil
	end

	raw_value, adc_mv = adc.read(gadc.ADC0)
	adc.close(gadc.ADC0)

	if type(adc_mv) ~= "number" or adc_mv < 0 then
		if log and log.error then
			log.error("gadc.read_wcs1500_adc0", "adc.read invalid", adc_mv)
		end
		return nil, nil, nil
	end

	return raw_value, adc_mv, adc_mv * gadc.WCS1500_DIVIDER_RATIO
end

return gadc
