love.graphics.setDefaultFilter('nearest', 'nearest')
-- tracks needs of all morphis
local object = require('libs.classic')
local hunger = require('src.needs.hunger')
local needTracker = object:extend()

local hungryIcon = love.graphics.newImage('icons/hungry-indicator-icon.png')

local needs = {}
needs.hunger = {}

function needTracker.new(need, morphi)
    if need == 'hunger' then
        local hungerNeed = hunger(morphi)
        table.insert(needs.hunger, hungerNeed)
        morphi.hunger = hungerNeed
    end
end

function needTracker.draw()
    for _, need in ipairs(needs.hunger) do
        if need.value <= 0 then
            local scale = .7
            love.graphics.draw(
                hungryIcon,
                need.morphi.x - hungryIcon:getWidth() / 2 * scale,
                need.morphi.y - need.morphi.height,
                0, scale, scale)
        end
    end
end

return needTracker
