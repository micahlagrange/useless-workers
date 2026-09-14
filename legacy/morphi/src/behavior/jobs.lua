local Timers = require('src.system.timer')

local function takeWanderJob(worker)
    local longRunning = true
    Timers.add(
        'flip_' .. worker.id,
        30,
        function() worker:flipFacing() end,
        longRunning)
    return {
        name = 'wander',
        canFlip = true,
    }
end

return takeWanderJob
