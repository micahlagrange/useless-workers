require('src.constants')
local object = require('libs.classic')
local Timers = require('src.system.timer')

local consumable = object:extend()
local consumables = {}
local Consumables = {} -- module

local function findIndexForConsumableID(name)
    --return 0 if none found
    for idx, p in ipairs(consumables) do
        if p.pkguid == name then
            return idx
        end
    end
    return 0
end

local function deleteConsumable(consum, name)
    local idx = findIndexForConsumableID(name)
    if idx > 0 then table.remove(consumables, idx) end

    consum.x = WASTE_LAND
    consum.y = WASTE_LAND
    pcall(function()
        consum.collider:setGravityScale(0)
        consum.collider:setCollisionClass('Ghost')
        consum.collider:setX(WASTE_LAND)
        consum.collider:setY(WASTE_LAND)
    end)
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

function consumable:new(x, y, scale)
    self.conguid = getUniqueID()
    self.x, self.y = x, y
    self.collider = World:newBSGRectangleCollider(
        self.x,
        self.y,
        TILE_SIZE * scale,
        TILE_SIZE * scale,
        2.5
    )
    self.collider:setCollisionClass(CollisionClasses.CONSUMABLE)
    self.collider:setObject(self)

    print('  -- new consumable ', self.conguid, ' x, y: ', x, y)
    table.insert(consumables, self)
end

function consumable:update()
    self.x, self.y = self.collider:getX(), self.collider:getY()
    self.angle = self.collider:getAngle()
end

function consumable:consum(collider)
    local pickup = collider:getObject()
    print('pickup ', pickup.pkguid)
    deleteConsumable(pickup, pickup.pkguid)
end

function Consumables.New(x, y, scale)
    return consumable(x, y, scale)
end

return Consumables
