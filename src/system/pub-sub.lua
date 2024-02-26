-- taken from https://github.com/michaeljosephpurdy/do-you-even-bocce/blob/main/src/mixins/pub-sub.lua

local PubSubMixin = {}

function PubSubMixin:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return self
end

function PubSubMixin:register_events(events)
    if not self.subscriptions then
        self.subscriptions = {}
    end
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
    for _, subscription in ipairs(self.subscriptions[event]) do
        subscription(payload)
    end
end

return PubSubMixin