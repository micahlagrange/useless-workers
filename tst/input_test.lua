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
    love.keypressed('3') -- FLOOR
    Stub.fingers = { 'c' }
    love.touchpressed('c', 300, 200)
    love.mousepressed(300, 200, 1, true)
    lu.assertNotNil(game.lineStart, 'the tap was ignored')
    love.mousereleased(300, 200, 1, true)
    love.touchreleased('c')
    lu.assertNil(game.lineStart)
end

-- A second finger turns a drag into a pinch: nothing gets built.
function TestInput:testAPinchCallsOffTheDrag()
    local game = H.game()
    love.keypressed('3')
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    love.mousepressed(300, 200, 1, true)
    lu.assertNotNil(game.lineStart)
    Stub.fingers = { 'a', 'b' }
    love.touchpressed('b', 400, 200)
    lu.assertNil(game.lineStart)
    local before = #game.world.sites
    love.mousereleased(300, 200, 1, true)
    lu.assertEquals(#game.world.sites, before)
end

-- iOS can stop sending the mouse events made up from a finger. Taps and
-- drags come from the touches alone, so nothing freezes when they stop.
function TestInput:testTouchesWorkWithoutAnyMouseEvents()
    local game = H.game()
    love.keypressed('3') -- FLOOR
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    lu.assertNotNil(game.lineStart, 'the tap was ignored')
    love.touchreleased('a', 300, 200)
    Stub.fingers = {}
    lu.assertNil(game.lineStart)
    -- a drag with SELECT is a pan, not a tap
    love.keypressed('1')
    Stub.fingers = { 'b' }
    love.touchpressed('b', 300, 200)
    love.touchmoved('b', 360, 230)
    love.touchmoved('b', 420, 260)
    lu.assertTrue(game.panStart and game.panStart.moved, 'the drag was not seen')
    love.touchreleased('b', 420, 260)
    Stub.fingers = {}
    lu.assertNil(game.panStart)
end

-- A finger LOVE stops listing without a release lets go of what it began.
function TestInput:testAVanishedFingerLetsGo()
    local game = H.game()
    love.keypressed('3')
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    lu.assertNotNil(game.lineStart)
    Stub.fingers = {}
    love.update(1 / 30)
    lu.assertNil(game.lineStart)
    Stub.fingers = { 'b' }
    love.touchpressed('b', 300, 200)
    lu.assertNotNil(game.lineStart, 'the next tap was ignored')
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

-- The gear menu stays open under buttons pressed over and over, and shuts
-- behind one that goes somewhere.
function TestInput:testGearMenuStaysOpenForRepeatPresses()
    local ui, game = H.ui(), H.game()
    tapButton('gear')
    lu.assertEquals(ui.dropdown, 'gear')
    local speed = game.speed or 1
    tapButton('speed')
    tapButton('speed')
    lu.assertNotEquals(game.speed or 1, speed)
    lu.assertEquals(ui.dropdown, 'gear')
    tapButton('log')
    lu.assertNil(ui.dropdown)
    lu.assertEquals(H.state(), 'log')
    H.setState('playing')
end

-- SOUND opens the mixer, which stays open while the levels move.
function TestInput:testMixerSetsEachChannel()
    local ui = H.ui()
    local Audio = require('src.audio')
    Audio.setVolume('music', 0.5)
    Audio.setVolume('alert', 1)
    tapButton('gear')
    tapButton('sound')
    lu.assertEquals(ui.dropdown, 'sound')
    tapButton('vol:music:+')
    tapButton('vol:alert:-')
    tapButton('vol:alert:-')
    lu.assertEquals(ui.dropdown, 'sound')
    lu.assertAlmostEquals(Audio.getVolume('music'), 0.6, 1e-9)
    lu.assertAlmostEquals(Audio.getVolume('alert'), 0.8, 1e-9)
    -- a tap at the bar's left end silences that channel
    love.draw()
    local bar
    for _, b in ipairs(ui.dropButtons) do if b.id == 'volbar:sfx' then bar = b end end
    Stub.fingers = { 't' }
    love.touchpressed('t', (bar.x + 1) * ui.scale, (bar.y + bar.h / 2) * ui.scale)
    love.touchreleased('t', (bar.x + 1) * ui.scale, (bar.y + bar.h / 2) * ui.scale)
    Stub.fingers = {}
    lu.assertEquals(Audio.getVolume('sfx'), 0)
    lu.assertEquals(ui.dropdown, 'sound')
    for _, c in ipairs(Audio.CHANNELS) do Audio.setVolume(c, 1) end
    ui.dropdown = nil
end

-- DEV, then FUN TEST, by finger: pick two morphis and a kind of fun, they
-- start at once, and the game is back on screen to watch them.
function TestInput:testFunTestByTouch()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    for _ = 1, 30 do love.update(1 / 30) end
    local game = H.game()
    tapButton('dev')
    lu.assertEquals(H.state(), 'tools')
    tapButton('funtest')
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

-- DETAILS on the picked morphi's strip opens what it is doing, and the
-- fun it is having is in the log from start to end.
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
    love.draw()
    local ui = H.ui()
    lu.assertNotNil(ui.doingButton, 'no DETAILS button on the strip')
    local r = ui.doingButton
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
    tapButton('dev')
    lu.assertEquals(H.state(), 'tools')
    love.draw()
    for _, b in ipairs(H.ui().panelButtons) do lu.assertNotEquals(b.id, 'funtest') end
    H.setState('playing')
end

os.exit(lu.LuaUnit.run())
