local Luafinding = require('libs.luafinding')
local Vector = require('libs.vector')

local Pathfinder = {}

-- Returns a list of {x, y} tiles from start to finish (start included), or nil.
function Pathfinder.find(world, sx, sy, tx, ty)
    if not world:isPassable(tx, ty) or not world:isPassable(sx, sy) then return nil end
    if sx == tx and sy == ty then return { { x = sx, y = sy } } end
    local check = function(pos) return world:isPassable(pos.x, pos.y) end
    local finder = Luafinding(Vector(sx, sy), Vector(tx, ty), check, false)
    local path = finder:GetPath()
    if not path then return nil end
    local out = {}
    for i, v in ipairs(path) do
        out[i] = { x = v.x, y = v.y }
    end
    if out[1].x ~= sx or out[1].y ~= sy then
        table.insert(out, 1, { x = sx, y = sy })
    end
    return out
end

return Pathfinder
