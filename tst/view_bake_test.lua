-- Micah: "clicking on something sometimes hangs for a second". Every change
-- to the map (a stash set out, a dig finished, a bridge laid) used to redraw
-- the whole 96x64 baked map in one frame. The world now logs which tiles
-- changed and the views redraw only those, with the ring around them.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
package.path = "./?.lua;./?/init.lua;" .. package.path
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Tileset = require('src.tileset')

-- Count what a rebuild draws.
local calls
local function count(name)
    rawset(love.graphics, name, function() calls[name] = (calls[name] or 0) + 1 end)
end
for _, n in ipairs({ 'rectangle', 'draw', 'clear', 'setScissor', 'print' }) do count(n) end
local function draws() return (calls.rectangle or 0) + (calls.draw or 0) + (calls.print or 0) end

local function grassTile(world)
    for x = 10, world.w - 10 do
        for y = 10, world.h - 10 do
            local t = world:get(x, y)
            if t.type == TILE_GRASS and t.storage == 0 and not t.node then return x, y end
        end
    end
end

TestChangeLog = {}

function TestChangeLog:testItSaysWhichTilesChanged()
    local world = World.generate(7, Rng.new(7))
    local v = world.version
    lu.assertEquals(world:changesSince(v), {})
    lu.assertNil(world:changesSince(-1), 'a view never drawn redraws everything')
    local x, y = grassTile(world)
    world:markStorage(x, y)
    world:setType(x + 1, y, TILE_DIRT)
    local c = world:changesSince(v)
    lu.assertEquals(#c, 2)
    lu.assertEquals(c[1], { x = x + 1, y = y })
    lu.assertEquals(c[2], { x = x, y = y })
    lu.assertEquals(#world:changesSince(v + 1), 1)
    -- a whole-map change, or a log that no longer reaches back: everything
    world:changed()
    lu.assertNil(world:changesSince(v))
    local v2 = world.version
    for i = 1, World.CHANGE_LOG + 5 do world:changed(1, 1) end
    lu.assertNil(world:changesSince(v2))
    lu.assertEquals(#world:changesSince(world.version - 3), 3)
end

TestBake = {}

for _, set in ipairs(Tileset.SETS) do
    TestBake['testOneStashRedrawsAFewTilesNotTheMap_' .. set] = function()
        Tileset.set(set)
        local world = World.generate(11, Rng.new(11))
        local view = Tileset.newView(world)
        calls = {}
        view:rebuildCanvas()
        local full = draws()
        lu.assertTrue((calls.clear or 0) >= 1)
        lu.assertTrue(full >= world.w * world.h, set .. ': the first bake drew ' .. full)
        -- nothing changed: nothing drawn
        calls = {}
        view:rebuildCanvas()
        lu.assertEquals(draws(), 0)
        -- one stash: the tiles within two of it, clipped to the 3x3 around it
        local x, y = grassTile(world)
        world:markStorage(x, y)
        calls = {}
        view:rebuildCanvas()
        local patch = draws()
        lu.assertNil(calls.clear, set .. ': one stash cleared the whole map')
        lu.assertTrue((calls.setScissor or 0) >= 2, set .. ': the redraw is not clipped')
        lu.assertTrue(patch > 0)
        lu.assertTrue(patch * 50 < full, set .. ': one stash drew ' .. patch .. ' of ' .. full)
        lu.assertEquals(view.canvasVersion, world.version)
        -- a big change (a new map) redraws everything again
        world:changed()
        calls = {}
        view:rebuildCanvas()
        lu.assertTrue(draws() >= full * 0.9)
    end
end

os.exit(lu.LuaUnit.run())
