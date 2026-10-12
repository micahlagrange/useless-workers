-- adapted from https://github.com/michaeljosephpurdy/do-you-even-bocce/blob/main/src/mixins/pub-sub.lua

local object = require('libs.classic')
local pubsub = object:extend()

function pubsub:new()
    self.subscriptions = {}
end

function pubsub:register_events(data)
    local events = {}
    -- normalize to a collection
    if type(data) ~= "table" then
        table.insert(events, data)
    else
        events = data
    end
    -- add all the events
    for _, event in pairs(events) do
        if self.subscriptions[event] == nil then
            self.subscriptions[event] = {}
        end
        print('registered event ', event)
    end
end

function pubsub:subscribe(event, fn)
    print('subscribe event ' .. event)
    table.insert(self.subscriptions[event], fn)
end

function pubsub:publish(event, payload)
    print('publish event ', event, payload)
    for _, subscription in ipairs(self.subscriptions[event]) do
        subscription(payload)
    end
end

return pubsub()
