local config = {}

config.phoneNum = "15025376653"
config.MQTT = {
    name = "developLink",
    host = "con-mqttn.developlink.cloud",
    port = 1883,
    clientId = "d864865085015494",
    username = "pe475014317757",
    password = "7c59ffbea4cb450283bbaa34d685c6d5",
    postTopic = "/pe475014317757/d864865085015494/dp/post",
    getTopic = "/pe475014317757/d864865085015494/dp/get",
    setTopic = "/pe475014317757/d864865085015494/dp/set",
    getReplyTopic = "/pe475014317757/d864865085015494/dp/get/reply",
    setReplyTopic = "/pe475014317757/d864865085015494/dp/set/reply"
}



return config