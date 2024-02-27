local collision = require('src.collision')
local inspect = require('libs.inspect')
local lu = require('libs.luaunit')

collision:new()
collision:loadJSON()
local intGrid = collision:findIntGrid()
lu.assertEquals(intGrid[1][1], 0)
lu.assertEquals(intGrid[#intGrid][#intGrid[#intGrid]], 1)

collision:IntGridToWinfieldRects(intGrid)