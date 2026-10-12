require('src.constants')
local object = require('libs.classic')
local Timers = require('src.system.timer')

local consumable = object:extend()
local consumables = {}
local Consumables = {} -- module

local function findIndexForConsumableID(conguid)
    --return 0 if none found
    for idx, p in ipairs(consumables) do
        if p.conguid == conguid then
            return idx
        end
    end
    return 0
end

local function cleanUpConsumables()
    local trash = World:queryCircleArea(WASTE_LAND, WASTE_LAND, 300)
    for _, collider in ipairs(trash) do
        print('delete consumable collider ', collider)
        print(pcall(function() collider:destroy() end))
    end
end

Timers.add('cleanUpConsumables', 20, cleanUpConsumables, true)
local counter = 0
local function getUniqueID()
    counter = counter + 1
    return counter
end

function consumable:new(consuminstance, scale)
    self.consuminstance = consuminstance
    self.conguid = getUniqueID()
    self.x, self.y = consuminstance.x, consuminstance.y
    self.collider = World:newBSGRectangleCollider(
        self.x,
        self.y,
        TILE_SIZE * scale,
        TILE_SIZE * scale,
        2.5
    )
    self.collider:setCollisionClass(Colliders.CONSUMABLE)
    self.collider:setObject(self)

    print('  -- new consumable ', self.conguid, ' x, y: ', x, y)
    table.insert(consumables, self)
end

function consumable:update()
    if self.trash then return end
    self.x, self.y = self.collider:getX(), self.collider:getY()
    self.angle = self.collider:getAngle()
end

function consumable:delete()
    self.trash = true

    local idx = findIndexForConsumableID(self.conguid)

    self.x, self.y = WASTE_LAND, WASTE_LAND

    pcall(function()
        self.collider:setGravityScale(0)
        self.collider:setCollisionClass('Ghost')
        self.collider:setX(WASTE_LAND)
        self.collider:setY(WASTE_LAND)
    end)

    if idx > 0 then table.remove(consumables, idx) end
end

function consumable:consum()
    print('consum ', self.conguid)
    self:delete()
end

function Consumables.New(x, y, scale)
    return consumable(x, y, scale)
end

return Consumables
