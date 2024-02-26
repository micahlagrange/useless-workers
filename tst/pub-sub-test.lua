local lu = require('libs.luaunit')


-- PubSub tests
local pubsub = require('src.system.pub-sub')
local ps = pubsub:new()

local testTable = {}
local testEvent = 'testEvent'

ps:register_events(testEvent)
ps:subscribe(testEvent, function(messag)
    table.insert(testTable, messag)
end)
ps:publish(testEvent, "themessage")

lu.assertEquals(testTable[1], "themessage")
