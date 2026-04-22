# wb 工程交接说明

## 1. 项目概览

本工程是一个基于 **Air780EPM + LuatOS** 的现场采集终端，主要负责以下业务：

- 采集两路温湿度数据
- 采集两路压差/气压数据
- 采集电池电压与电流传感器数据
- 读取门磁状态
- 通过 AirLBS 获取基站定位
- 根据阈值生成本地告警与短信告警
- 通过 MQTT 上报采集结果，并接收云端配置读写
- 根据 `GPIO21` 的 VBUS 状态在 USB 供电模式与电池供电模式之间切换

运行入口在 [code/main.lua](code/main.lua)，主业务编排在 [code/application.lua](code/application.lua)。

## 2. 目录结构

| 路径 | 说明 |
| --- | --- |
| [code](code) | 设备脚本主目录，部署到 LuatOS 时重点关注这里 |
| [code/tests](code/tests) | Lua 单元测试目录，主要覆盖应用逻辑与模块边界 |
| [code/docs/superpowers](code/docs/superpowers) | 历史设计/计划文档，不参与运行 |
| [code/luatos](code/luatos) | LuatOS SoC 固件文件 |
| [hw](hw) | 硬件原理图与工程文件 |
| [硬件方案v100.pdf](./硬件方案v100.pdf) | 方案级说明文档 |

说明：

- `code/.worktrees` 是历史辅助工作区，不是当前主工程运行目录。
- 日常开发、调试、加功能时，应优先修改 [code](code) 下的文件。

## 3. 启动流程

启动链路如下：

1. [code/main.lua](code/main.lua) 加载 `sys`、`config`、`application`。
2. [code/application.lua](code/application.lua) 初始化 `fskv`、GPIO、温湿度、压差、AirLBS、MQTT。
3. 进入周期采集循环：
   - [code/app_collect.lua](code/app_collect.lua) 生成原始采集快照
   - [code/app_algorithm.lua](code/app_algorithm.lua) 做平滑滤波
   - [code/app_alarm.lua](code/app_alarm.lua) 做阈值判断与短信触发
   - [code/app_state.lua](code/app_state.lua) 保存最新快照
   - [code/gmqtt.lua](code/gmqtt.lua) 转换成网关 DP 并上报
4. [code/ggpio.lua](code/ggpio.lua) 的门磁边沿事件会触发单独的门开超时观察逻辑。
5. [code/app_power.lua](code/app_power.lua) 根据 `GPIO21` 的 VBUS 状态决定是否进入低功耗。

## 4. 模块职责

### 4.1 业务主线

| 文件 | 职责 | 常见改动场景 |
| --- | --- | --- |
| [code/application.lua](code/application.lua) | 应用主编排，负责初始化、主循环、门磁事件处理 | 增加新的业务流程、调整主循环节奏 |
| [code/app_collect.lua](code/app_collect.lua) | 聚合所有传感器读数并生成统一 `snapshot` | 增加新的采集字段 |
| [code/app_algorithm.lua](code/app_algorithm.lua) | 对温湿度、电流做去抖/平滑处理 | 调整滤波窗口、算法策略 |
| [code/app_alarm.lua](code/app_alarm.lua) | 依据阈值和状态机生成告警 | 调整阈值规则、短信内容 |
| [code/app_power.lua](code/app_power.lua) | 判定 USB/电池供电模式并控制休眠 | 排查电源切换、调整唤醒策略 |

### 4.2 配置与状态

| 文件 | 职责 | 备注 |
| --- | --- | --- |
| [code/config.lua](code/config.lua) | 静态默认配置、字段类型、云端允许修改字段 | 包含 MQTT 默认参数与阈值默认值 |
| [code/app_config.lua](code/app_config.lua) | 默认配置与 `fskv` 持久化配置合并、更新、迁移 | `app:config` 是持久化键 |
| [code/app_state.lua](code/app_state.lua) | 缓存并持久化最近一次快照 | `app:latest` 是持久化键 |

### 4.3 外设与平台适配

| 文件 | 职责 |
| --- | --- |
| [code/ggpio.lua](code/ggpio.lua) | 板级 GPIO 封装，管理 3V3/5V/ADC 使能、门磁输入、VBUS 检测 |
| [code/gadc.lua](code/gadc.lua) | 电池电压与电流 ADC 读取 |
| [code/gsht30.lua](code/gsht30.lua) | 两路 SHT30 温湿度读取 |
| [code/gbaro.lua](code/gbaro.lua) | 两路串口压差/气压传感器协议解析 |
| [code/glbs.lua](code/glbs.lua) | AirLBS 请求、缓存与限频 |
| [code/app_sms.lua](code/app_sms.lua) | 短信发送封装，依赖网络就绪事件 |

### 4.4 云端通信

| 文件 | 职责 |
| --- | --- |
| [code/iot.lua](code/iot.lua) | MQTT 底层封装，负责建连、订阅、发布、回复 |
| [code/gmqtt.lua](code/gmqtt.lua) | 业务层 MQTT 适配，把 `snapshot` 映射为平台 DP，并处理配置下发 |

## 5. 关键数据结构

### 5.1 采集快照 `snapshot`

[code/app_collect.lua](code/app_collect.lua) 生成的统一快照大致包含：

- `timestamp` / `timestamp_ms`
- `battery_mv` / `battery_percent`
- `current_raw` / `current_mv` / `current_sensor_mv`
- `door_open`
- `location`
- `temp_hum`
- `pressure`
- `err`

后续模块都围绕这份快照工作：

- `app_algorithm` 在原快照基础上做平滑
- `app_alarm` 写入告警文本
- `app_state` 持久化最新值
- `gmqtt` 将其映射成平台 DP

### 5.2 云端配置

云端允许修改的字段由 [code/config.lua](code/config.lua) 中的 `GATEWAY_CONFIG_FIELDS` 定义，更新流程为：

1. 云端向 `setTopic` 下发 `dp.config`
2. [code/gmqtt.lua](code/gmqtt.lua) 过滤允许修改的字段
3. [code/app_config.lua](code/app_config.lua) 校验类型并持久化到 `fskv`

## 6. 供电与低功耗

当前供电模式由 [code/app_power.lua](code/app_power.lua) 决定：

- `GPIO21` 高电平：判定为 `USB`
- `GPIO21` 低电平：判定为 `BATTERY`
- 如果 VBUS 检测失败：保守回退到 `USB`

相关硬件与板级控制位见 [code/ggpio.lua](code/ggpio.lua)：

- `GPIO24`：ADC 使能
- `GPIO25`：3.3V 使能
- `GPIO27`：5V 使能
- `GPIO21`：VBUS 检测
- `WAKEUP0`：门磁输入

电池模式下会：

- 使用 `battery_interval_ms`
- 提前 5 秒配置唤醒
- 进入 `pm.LIGHT` 低功耗

## 7. 开发与测试

推荐在 [code](code) 目录下执行测试与语法检查。

### 7.1 运行全部测试

```powershell
Get-ChildItem .\tests\*_test.lua | ForEach-Object {
    & 'D:\tool\lua\bin\lua.cmd' $_.FullName
}
```

### 7.2 检查 Lua 语法

```powershell
Get-ChildItem .\*.lua | ForEach-Object {
    & 'D:\tool\lua\bin\luac.cmd' -p $_.FullName
}
```

### 7.3 调试建议

- 看启动是否正常，优先关注 `application`、`gmqtt`、`glbs`、`app_power` 日志。
- 排查供电模式时，重点看 `VBUS检测初始化`、`GPIO21状态变化`、`供电模式判定`。
- 排查门磁即时告警时，重点看 `APP_DOOR_EDGE` 相关日志。
- 排查云端配置下发时，重点看 `gmqtt` 的 `收到云端消息`、`已回复配置写入` 日志。

## 8. 接手建议

新工程师接手时，建议按以下顺序阅读：

1. [README.md](README.md)
2. [code/main.lua](code/main.lua)
3. [code/application.lua](code/application.lua)
4. [code/app_collect.lua](code/app_collect.lua)
5. [code/app_alarm.lua](code/app_alarm.lua)
6. [code/gmqtt.lua](code/gmqtt.lua)
7. [code/ggpio.lua](code/ggpio.lua) 与 [hw](hw)

常见需求的入口文件：

- 改默认阈值或默认手机号： [code/config.lua](code/config.lua)
- 改云端可配字段： [code/config.lua](code/config.lua)、[code/app_config.lua](code/app_config.lua)、[code/gmqtt.lua](code/gmqtt.lua)
- 改告警策略： [code/app_alarm.lua](code/app_alarm.lua)
- 改休眠/唤醒策略： [code/app_power.lua](code/app_power.lua)
- 改上传字段映射： [code/gmqtt.lua](code/gmqtt.lua)

## 9. 当前维护注意事项

- `config.lua` 中目前直接保存了 MQTT 参数、AirLBS 参数和短信号码，后续如果进入正式量产，建议迁移到安全配置流程。
- 代码中的数组型传感器结果既有 `0/1` 索引，也有 `1/2` 索引，改动时一定先看对应模块当前约定。
- 原理图和硬件工程都在仓库中，涉及 GPIO、电源、传感器接线的改动时，不要只看软件。
