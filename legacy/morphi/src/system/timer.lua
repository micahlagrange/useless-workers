local inspect = require('libs.inspect')
local pubsub = require('src.system.pub-sub')

local timers = {}
local Timer = {}

function Timer.add(name, timeSecs, callback, longRunning)
    table.insert(timers, {
        name = name,
        value = timeSecs or 5,
        originalValue = timeSecs or 5,
        expireEvent = EVENTS.Timer.TIMER_EXPIRED .. '_' .. name
    })
    print('longRunning ', inspect(longRunning))
    timers[#timers].longLived = longRunning
    print('add timer ' .. name .. '..' .. #timers)
    pubsub:register_events(timers[#timers].expireEvent)
    pubsub:subscribe(timers[#timers].expireEvent, callback)
    return timers[#timers].expireEvent
end

function Timer.reset(i)
    print('reset timer ' .. timers[i].name)
    timers[i].value = timers[i].originalValue
end

function Timer.update(dt)
    for i, t in pairs(timers) do
        Timer.tick(i, t, dt)
    end
end

function Timer.remove(i)
    print('remove ' .. i)
    return table.remove(timers, i)
end

function Timer.tick(i, timer, dt)
    if timer.value == nil then return end
    timer.value = timer.value - dt
    if timer.value <= 0 then
        if timer.longLived then
            Timer.reset(i)
        else
            Timer.remove(i)
        end
        pubsub:publish(timer.expireEvent)
    end
end

return Timer
