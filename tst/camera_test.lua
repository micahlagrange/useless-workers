local lu = require('libs.luaunit')
require('src.constants')
local Camera = require('src.camera')

TestCamera = {}

-- The bars cover the top and bottom of the screen: scrolled all the way
-- down, the map's bottom edge sits on the bottom bar, not under it.
function TestCamera:testMapEdgesStopAtTheBars()
    local cam = Camera.new(40, 40, 800, 600)
    cam:setInsets(50, 120)
    cam.scale = 2
    cam:pan(0, 1e6)
    local bottom = cam:toScreen(0, 40 * TILE_SIZE).y
    lu.assertAlmostEquals(bottom, 600 - 120, 0.01)
    cam:pan(0, -1e6)
    local top = cam:toScreen(0, 0).y
    lu.assertAlmostEquals(top, 50, 0.01)
end

-- A map smaller than the strip between the bars sits centred in that strip.
function TestCamera:testSmallMapCentresBetweenTheBars()
    local cam = Camera.new(10, 5, 800, 600)
    cam:setInsets(40, 80)
    cam:fitWorld()
    local top, bottom = cam:toScreen(0, 0).y, cam:toScreen(0, 5 * TILE_SIZE).y
    lu.assertTrue(top >= 40 - 0.01)
    lu.assertTrue(bottom <= 600 - 80 + 0.01)
    lu.assertAlmostEquals(top - 40, (600 - 80) - bottom, 0.5)
end

os.exit(lu.LuaUnit.run())
