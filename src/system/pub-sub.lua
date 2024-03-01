-- taken from https://github.com/michaeljosephpurdy/do-you-even-bocce/blob/main/src/mixins/pub-sub.lua
local object = require('libs.classic')

local PubSubMixin = object:extend()

function PubSubMixin:new()
    self.subscriptions = {}
end

function PubSubMixin:register_events(events)
    if type(events) == "table" then
        for _, name in pairs(events) do
            self.subscriptions[name] = {}
        end
        return
    end
    self.subscriptions[events] = {}
end

function PubSubMixin:subscribe(event, fn)
    table.insert(self.subscriptions[event], fn)
end

function PubSubMixin:publish(event, payload)
    print('publish ' .. event)
    for _, subscription in ipairs(self.subscriptions[event]) do
        subscription(payload)
    end
end

local instance = PubSubMixin()
return instance
