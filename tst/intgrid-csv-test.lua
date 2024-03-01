-- world mocks
World = {}
RectCollider = {}
function RectCollider:setType(x,x,x,x,x)
end
function World:newRectangleCollider(x,x,x,x,x,x)
    return RectCollider
end

local collision = require('src.collision')
local inspect = require('libs.inspect')
local lu = require('libs.luaunit')

function LDtkParser:readFile(path)
    return ReadFile(path)
end

collision:new()
collision:loadJSON()
local intGrid = collision:findIntGrid()
lu.assertEquals(intGrid[1][1], 0)
lu.assertEquals(intGrid[#intGrid][#intGrid[#intGrid]], 1)

collision:IntGridToWinfieldRects(intGrid)