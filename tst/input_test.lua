-- Input that has to keep working on a phone.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()

TestInput = {}

function TestInput:setUp()
    Stub.width, Stub.height = 852, 393
    H.ui().touch = true
    love.resize(852, 393)
    H.newLevel(2, 'arcade', 1)
    H.closeGoal()
    Stub.fingers = {}
    love.update(0) -- forget fingers an earlier test left down, as a frame would
end

-- iOS can cancel a touch without a release. A pinch whose second finger
-- never says goodbye must not leave every later tap ignored.
function TestInput:testALostReleaseDoesNotFreezeTaps()
    Stub.fingers = { 'a', 'b' }
    love.touchpressed('a', 300, 200)
    love.touchpressed('b', 400, 200)
    love.touchreleased('a')
    -- 'b' is never released; LOVE just stops listing it
    Stub.fingers = {}
    love.update(1 / 30)
    local game = H.game()
    Stub.fingers = { 'c' }
    love.touchpressed('c', 300, 200)
    love.mousepressed(300, 200, 1, true)
    lu.assertNotNil(game.paint, 'the tap was ignored')
    love.mousereleased(300, 200, 1, true)
    love.touchreleased('c')
    lu.assertNil(game.paint)
end

-- The water square the camera shows nearest the screen's middle.
local function waterOnScreen(game)
    local best, bestD
    for x = 1, game.world.w do
        for y = 1, game.world.h do
            local t = game.world:get(x, y)
            if t.type == TILE_WATER and not t.site then
                local p = game.camera:toScreen((x - 0.5) * TILE_SIZE, (y - 0.5) * TILE_SIZE)
                local d = math.abs(p.x - 426) + math.abs(p.y - 196)
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
    end
    return best
end

-- A second finger turns a drag into a pinch: nothing gets built.
function TestInput:testAPinchCallsOffTheDrag()
    local game = H.game()
    game.world.stock.logs = 20
    local p = waterOnScreen(game)
    lu.assertNotNil(p, 'some water to bridge')
    Stub.fingers = { 'a' }
    love.touchpressed('a', p.x, p.y)
    love.touchmoved('a', p.x + 30, p.y)
    lu.assertNotNil(game.paint)
    lu.assertEquals(game.paint.kind, 'bridge')
    Stub.fingers = { 'a', 'b' }
    love.touchpressed('b', 400, 200)
    lu.assertNil(game.paint)
    local before = #game.world.sites
    love.touchreleased('a', p.x + 30, p.y)
    lu.assertEquals(#game.world.sites, before)
end

-- iOS can stop sending the mouse events made up from a finger. Taps and
-- drags come from the touches alone, so nothing freezes when they stop.
function TestInput:testTouchesWorkWithoutAnyMouseEvents()
    local game = H.game()
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    lu.assertNotNil(game.paint, 'the tap was ignored')
    love.touchreleased('a', 300, 200)
    Stub.fingers = {}
    lu.assertNil(game.paint)
    -- a drag that starts on open ground is a pan, not a tap
    local hud = H.hud()
    hud:close()
    local open
    for x = 1, game.world.w do
        for y = 1, game.world.h do
            local t = game.world:get(x, y)
            if not open and t.type == TILE_GRASS and not t.node and not t.site then
                local sp = game.camera:toScreen((x - 0.5) * TILE_SIZE, (y - 0.5) * TILE_SIZE)
                if sp.x > 100 and sp.x < 700 and sp.y > 100 and sp.y < 300 then open = sp end
            end
        end
    end
    lu.assertNotNil(open)
    Stub.fingers = { 'b' }
    love.touchpressed('b', open.x, open.y)
    love.touchmoved('b', open.x + 60, open.y + 30)
    love.touchmoved('b', open.x + 120, open.y + 60)
    lu.assertTrue(game.paint and game.paint.moved and game.paint.kind == 'pan', 'the drag was not seen')
    love.touchreleased('b', open.x + 120, open.y + 60)
    Stub.fingers = {}
    lu.assertNil(game.paint)
    lu.assertFalse(hud:isOpen(), 'a pan opens no ring')
end

-- A finger LOVE stops listing without a release lets go of what it began.
function TestInput:testAVanishedFingerLetsGo()
    local game = H.game()
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    lu.assertNotNil(game.paint)
    Stub.fingers = {}
    love.update(1 / 30)
    lu.assertNil(game.paint)
    Stub.fingers = { 'b' }
    love.touchpressed('b', 300, 200)
    lu.assertNotNil(game.paint, 'the next tap was ignored')
    love.touchreleased('b', 300, 200)
end

-- A finger tap on a Toybox top bar button, found by id after a frame.
local function tapButton(id)
    love.draw()
    local ui = H.ui()
    local found
    for _, b in ipairs(ui.topButtons) do if b.id == id and not found then found = b end end
    lu.assertNotNil(found, 'no ' .. id .. ' button')
    local x, y = (found.x + found.w / 2) * ui.scale, (found.y + found.h / 2) * ui.scale
    Stub.fingers = { 't' }
    love.touchpressed('t', x, y)
    love.touchreleased('t', x, y)
    Stub.fingers = {}
    return found
end

-- A finger tap on a button of the menu sheet (they act on release).
local function tapMenu(id, at)
    local ui = H.ui()
    local found
    -- a short screen scrolls the menu: look for it from the top down
    ui.menuScroll = 0
    for _ = 1, 20 do
        love.draw()
        for _, b in ipairs(ui.panelButtons) do if b.id == id and not found and b.h >= 40 then found = b end end
        if found then break end
        ui.menuScroll = ui.menuScroll + 40
    end
    lu.assertNotNil(found, 'no ' .. id .. ' in the menu')
    local x = ((at and (found.x + at)) or (found.x + found.w / 2)) * ui.scale
    local y = (found.y + found.h / 2) * ui.scale
    Stub.fingers = { 'm' }
    love.touchpressed('m', x, y)
    love.touchreleased('m', x, y)
    Stub.fingers = {}
end

-- Speed and pause are one tap each, always on the bar.
function TestInput:testSpeedAndPauseAreOneTap()
    local game = H.game()
    local speed = game.speed or 1
    tapButton('speed')
    lu.assertNotEquals(game.speed or 1, speed)
    local paused = game.paused == true
    tapButton('pause')
    lu.assertEquals(game.paused == true, not paused)
    tapButton('pause')
    lu.assertEquals(game.paused == true, paused)
end

-- The menu holds the sound: each channel's - and +, and a tap on the bar.
function TestInput:testMenuSetsEachChannel()
    local Audio = require('src.audio')
    Audio.setVolume('music', 0.5)
    Audio.setVolume('alert', 1)
    tapButton('menu')
    lu.assertEquals(H.state(), 'menu')
    tapMenu('vol:music:+')
    tapMenu('vol:alert:-')
    tapMenu('vol:alert:-')
    lu.assertEquals(H.state(), 'menu')
    lu.assertAlmostEquals(Audio.getVolume('music'), 0.6, 1e-9)
    lu.assertAlmostEquals(Audio.getVolume('alert'), 0.8, 1e-9)
    -- a tap at the bar's left end silences that channel
    tapMenu('volbar:sfx', 1)
    lu.assertEquals(Audio.getVolume('sfx'), 0)
    for _, c in ipairs(Audio.CHANNELS) do Audio.setVolume(c, 1) end
    -- going back to the title asks once
    tapMenu('title')
    lu.assertEquals(H.ui().menuConfirm, 'title')
    tapMenu('confirm:no')
    lu.assertNil(H.ui().menuConfirm)
    tapMenu('carryon')
    lu.assertEquals(H.state(), 'playing')
end

os.exit(lu.LuaUnit.run())
