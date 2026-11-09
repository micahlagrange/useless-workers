-- Input that has to keep working on a phone.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Worker = require('src.worker')
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

-- A finger tap on a top bar, dropdown or panel button, found by id after a frame.
local function tapButton(id)
    love.draw()
    local ui = H.ui()
    local found
    for _, list in ipairs({ ui.dropButtons or {}, ui.topButtons, ui.panelButtons or {} }) do
        for _, b in ipairs(list) do if b.id == id and not found then found = b end end
    end
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

-- The menu's tester corner, then FUN TEST, by finger: pick two morphis and
-- a kind of fun, they start at once, and the game is back on screen.
function TestInput:testFunTestByTouch()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    for _ = 1, 30 do love.update(1 / 30) end
    local game = H.game()
    tapButton('menu')
    lu.assertEquals(H.state(), 'menu')
    tapMenu('funtest')
    lu.assertEquals(H.state(), 'funtest')
    -- a kind with nobody picked starts nothing
    tapButton('fk:dance')
    lu.assertEquals(H.state(), 'funtest')
    -- the buttons are numbered by place in the band, babies and eggs not listed
    local grown = {}
    for i, w in ipairs(game.workers) do if w:isWorking() then grown[#grown + 1] = i end end
    lu.assertTrue(#grown >= 2)
    tapButton('fm:' .. grown[1])
    tapButton('fm:' .. grown[#grown])
    tapButton('fk:dance')
    lu.assertEquals(H.state(), 'playing')
    local a, b = game.workers[grown[1]], game.workers[grown[#grown]]
    lu.assertNotNil(a.play)
    lu.assertEquals(a.play, b.play)
    lu.assertEquals(a.play.category, 'dance')
    lu.assertTrue(a.play.dev)
    local pl = a.play
    local bubbles = 0
    for _ = 1, 30 * 70 do
        love.update(1 / 30)
        if pl.a.bubble and pl.a.bubble.text == pl.convo[1] then bubbles = bubbles + 1 end
        if not pl.a.play then break end
    end
    lu.assertTrue(bubbles > 0, 'the first line was never said')
    lu.assertNil(pl.a.play, 'the dance never ended')
    -- it is in the run stats and the news
    local who = pl.a.name .. ' and ' .. pl.b.name
    local event, news
    for _, e in ipairs(game.stats.events) do if e.kind == 'play' and e.who == who then event = e end end
    for _, e in ipairs(game.log) do if e.text:find(who, 1, true) then news = e end end
    lu.assertNotNil(event)
    lu.assertEquals(event.text, 'dance: ' .. pl.convo.title)
    lu.assertNotNil(news)
end

-- DETAILS on the morphi's ring opens what it is doing, and the fun it is
-- having is in the log from start to end.
function TestInput:testDetailsButtonAndFunInTheLog()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    for _ = 1, 30 do love.update(1 / 30) end
    local game = H.game()
    local grown = {}
    for _, w in ipairs(game.workers) do if w:isWorking() then grown[#grown + 1] = w end end
    local a, b = grown[1], grown[2]
    game.selectedWorker = a
    love.draw()
    local pl = Worker.playPair(a, b, 'philosophize')
    lu.assertNotNil(pl)
    for _ = 1, 30 * 12 do love.update(1 / 30) end
    local ui, hud = H.ui(), H.hud()
    hud:close()
    local p = game.camera:toScreen(a.x, a.y - 4)
    Stub.fingers = { 't' }
    love.touchpressed('t', p.x, p.y)
    love.touchreleased('t', p.x, p.y)
    Stub.fingers = {}
    lu.assertTrue(hud:isOpen() and hud.ring.worker == a, 'the ring opens on the morphi')
    love.draw()
    local r
    for _, b in ipairs(hud.buttons or {}) do if b.item.id == 'details' then r = b end end
    lu.assertNotNil(r, 'no DETAILS on the ring')
    local x, y = (r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale
    Stub.fingers = { 't' }
    love.touchpressed('t', x, y)
    love.touchreleased('t', x, y)
    Stub.fingers = {}
    lu.assertEquals(H.state(), 'doing')
    love.draw()
    for _ = 1, 30 * 40 do love.update(1 / 30) end
    love.draw()
    love.keypressed('escape')
    lu.assertEquals(H.state(), 'playing')
    local who = a.name .. ' and ' .. b.name
    local started, ended = false, false
    for _, e in ipairs(game.log) do
        if e.text:find(who, 1, true) and e.text:find('started', 1, true) then started = true end
        if e.text:find(who, 1, true) and not e.text:find('started', 1, true) then ended = true end
    end
    lu.assertTrue(started, 'the start of the fun is not in the log')
    lu.assertTrue(ended, 'the end of the fun is not in the log')
end

-- FUN TEST is a free play tool: an arcade level has no morale to lift.
function TestInput:testNoPlayNowInArcade()
    tapButton('menu')
    lu.assertEquals(H.state(), 'menu')
    local ui = H.ui()
    ui.menuScroll = 0
    for _ = 1, 20 do
        love.draw()
        for _, b in ipairs(ui.panelButtons) do lu.assertNotEquals(b.id, 'funtest') end
        ui.menuScroll = ui.menuScroll + 40
    end
    tapMenu('carryon')
    lu.assertEquals(H.state(), 'playing')
end

os.exit(lu.LuaUnit.run())
