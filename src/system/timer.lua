local object = require('libs.classic')
local pubsub = require('src.system.pub-sub')
assert(pubsub ~= nil, "pubsub is nil in timer.lua")

local timers = {}

Timer = object:extend()
Timer.EVENTS = {
    TIMER_EXPIRED = "TIMER_EXPIRED"
}

function Timer:new()
    pubsub:register_events(Timer.EVENTS)
end

function Timer:add(name, timeSecs, callback, longLived)
    table.insert(timers, {
        name = name,
        value = timeSecs or 5,
        originalValue = timeSecs or 5,
    })
    timers[#timers].longLived = longLived == true
    pubsub:subscribe(Timer.EVENTS.TIMER_EXPIRED, callback)
    print('add.' .. name .. '..' .. #timers)
end

function Timer:reset(i)
    print('reset ' .. timers[i].name)
    timers[i].value = timers[i].originalValue
    print('timer ' .. timers[i].value)
end

function Timer:update(dt)
    for i, t in pairs(timers) do
        self:tick(i, t, dt)
    end
end

function Timer:remove(i)
    print('remove ' .. i)
    return table.remove(timers, i)
end

function Timer:tick(i, timer, dt)
    if timer.value == nil then return end
    timer.value = timer.value - dt
    if timer.value <= 0 then
        if timer.longLived then
            self:reset(i)
        else
            self:remove(i)
        end
        pubsub:publish(Timer.EVENTS.TIMER_EXPIRED, timer.name)
    end
end

return Timer()
