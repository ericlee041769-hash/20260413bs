-- 固件脚本入口。
-- 这里只做最小初始化：加载核心模块、启动应用主流程、交给 LuatOS 事件循环。
PROJECT = "Air780EPM"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.config = require("config")
_G.application = require("application")

application.start()
sys.run()
