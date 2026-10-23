-- The tile set switch: remembered on disk, a renderer per set, and the
-- rogue set draws every kind of thing as a glyph without falling over.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Tileset = require('src.tileset')
local View = require('src.view')
local Rogue = require('src.view_rogue')

-- a disk for the setting
local disk = {}
love.filesystem.write = function(name, data) disk[name] = data return true end
love.filesystem.read = function(name) return disk[name] end
love.filesystem.getInfo = function(name) return disk[name] and {} or nil end

love.load()

local function step(n)
    for _ = 1, n or 1 do love.update(1 / 30) end
end

local function frame()
    Stub.texts = {}
    love.draw()
    local seen = {}
    for _, t in ipairs(Stub.texts) do seen[t.text] = (seen[t.text] or 0) + 1 end
    return seen
end

TestTileset = {}

function TestTileset:setUp()
    disk = {}
    Tileset.set('classic')
end

function TestTileset:testDefaultAndUnknownNames()
    lu.assertEquals(Tileset.current(), 'classic')
    lu.assertFalse(Tileset.set('neon'))
    lu.assertEquals(Tileset.current(), 'classic')
    lu.assertEquals(Tileset.label(), 'CLASSIC')
end

function TestTileset:testCycleIsRemembered()
    lu.assertEquals(Tileset.cycle(), 'rogue')
    lu.assertEquals(disk[Tileset.FILE], 'rogue')
    lu.assertEquals(Tileset.cycle(), 'classic')
    lu.assertEquals(disk[Tileset.FILE], 'classic')
    -- what the disk says wins at load, odd line endings and all
    disk[Tileset.FILE] = 'rogue\r\n'
    Tileset.load()
    lu.assertEquals(Tileset.current(), 'rogue')
    disk[Tileset.FILE] = 'nonsense'
    Tileset.load()
    lu.assertEquals(Tileset.current(), 'rogue')
end

function TestTileset:testTKeySwapsTheRendererInPlay()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    step(10)
    local game = H.game()
    lu.assertEquals(getmetatable(game.view), View)
    lu.assertEquals(game.tileset, 'classic')
    local classic = frame()
    lu.assertNil(classic['@'])
    love.keypressed('t')
    lu.assertEquals(getmetatable(game.view), Rogue)
    lu.assertEquals(game.tileset, 'rogue')
    lu.assertEquals(Tileset.current(), 'rogue')
    local rogue = frame()
    -- every morphi is its species' letter, and the ground is glyphs: at least one per tile
    local expected = {}
    for _, w in ipairs(game.workers) do
        local g = Rogue.SPECIES_GLYPH[w.sheet]
        lu.assertNotNil(g, 'no glyph for ' .. tostring(w.sheet))
        expected[g] = (expected[g] or 0) + 1
    end
    for g, n in pairs(expected) do lu.assertTrue((rogue[g] or 0) >= n, g .. ' drawn ' .. tostring(rogue[g]) .. ' < ' .. n) end
    local ground = 0
    for _, glyphs in pairs(Rogue.GROUND) do
        for _, g in ipairs(glyphs) do ground = ground + (rogue[g] or 0) end
    end
    lu.assertTrue(ground >= game.world.w * game.world.h, 'ground glyphs: ' .. ground)
    love.keypressed('t')
    lu.assertEquals(getmetatable(game.view), View)
    lu.assertEquals(game.tileset, 'classic')
end

function TestTileset:testTilesButtonIsOnTheTopBar()
    local ui = H.ui()
    local found = false
    for _, d in ipairs(ui.quickDefs) do if d.id == 'tiles' then found = true end end
    lu.assertTrue(found)
end

function TestTileset:testRogueDrawsEveryKindOfThing()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    step(5)
    local game = H.game()
    Tileset.set('rogue')
    local view = Tileset.newView(game.world)
    lu.assertEquals(getmetatable(view), Rogue)
    local world = game.world
    -- one site of each kind, a bin and a bed in the world, items on the floor and in a bin
    local kinds = { SITE_MINE, SITE_STORAGE, SITE_BIN, SITE_BED, SITE_WALL, SITE_DOOR, SITE_BRIDGE }
    for i, kind in ipairs(kinds) do
        world.sites[#world.sites + 1] = { kind = kind, x = 2 + i * 2, y = 2, claimedBy = (i % 2 == 0) and 1 or nil }
    end
    local hud = H.ui().fonts.hud
    love.graphics.setFont(hud)
    Stub.texts = {}
    view:rebuildCanvas()
    view:drawWorld()
    view:drawBreakroom()
    view:drawStorage()
    view:drawFloors()
    view:drawBeds()
    view:drawNodes(1)
    view:drawItems(1)
    view:drawSites(1)
    for _, kind in ipairs({ SITE_BIN, SITE_BED, SITE_DOOR, SITE_WALL, SITE_STORAGE }) do
        view:drawGhost(kind, 3, 3, true)
        view:drawGhost(kind, 3, 3, false)
    end
    view:drawFocus(2, 2, 1)
    view:drawWorkers(game.workers, 1, game.workers[1])
    local seen = {}
    for _, t in ipairs(Stub.texts) do seen[t.text] = true end
    for _, g in ipairs({ Rogue.GLYPH.binLeft, Rogue.GLYPH.binRight, Rogue.GLYPH.bed, Rogue.GLYPH.wall, Rogue.GLYPH.door, Rogue.GLYPH.bridge, Rogue.GLYPH.floorSpot, Rogue.GLYPH.fire, Rogue.SPECIES_GLYPH[game.workers[1].sheet], 'HOME' }) do
        lu.assertTrue(seen[g], 'never drew ' .. g)
    end
    -- the font the HUD had is the font it gets back
    lu.assertEquals(love.graphics.getFont(), hud)
end

os.exit(lu.LuaUnit.run())
