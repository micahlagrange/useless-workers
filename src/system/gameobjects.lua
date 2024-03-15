local inspect = require "libs.inspect"
-- The list of objects that are drawable in the game that every loop are drawn at their locations
local objects = {}
local GameObjects = {}

function GameObjects.add(obj)
    table.insert(objects, obj)
end

function GameObjects.remove(idx)
    table.remove(objects, idx)
end

function GameObjects.reset()
    objects = {}
end

function GameObjects.update_all(dt)
    -- each object needs to implement :update()
    for _, obj in ipairs(objects) do
        obj:update(dt)
    end
end

function GameObjects.draw_all()
    -- each object needs to implement :draw()
    for _, obj in ipairs(objects) do
        obj:draw()
    end
end

function GameObjects.get_all_objects()
    return objects
end

return GameObjects
