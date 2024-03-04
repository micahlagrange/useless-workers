local object = require('libs.classic')
local Timers = require('src.system.timer')

local hunger = object:extend()
local identifier = 1

function hunger:new(morphi, val)
    -- default to 75 hp, meaning 15 minutes to lose all hunger points with a loss of 1
    self.value = val or 75
    self.interval = 20 -- every n seconds remove hunger
    self.loss = 1      -- n * 1 hunger point removed per interval
    self.timer = Timers.add(
        EVENTS.Hunger.HUNGER_DEGRADED,
        self.interval,
        function() self:degrade() end,
        true)
    self.id = identifier
    self.hungry = false
    self.morphi = morphi -- the entity containing this hunger bar
end

function hunger:degrade()
    if not self.hungry then
        self.value = self.value - 1 * self.loss
        print(self.morphi.name, ' hunger degrade to ', self.value)
        if self.value <= 0 then
            self.hungry = true
        end
    end
end

return hunger
