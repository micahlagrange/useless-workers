-- Chatter on the Toybox HUD (epic-chatter on top of epic-toybox-radial-ui):
-- the CHAT toy button and its unread badge, a tapped line opening that
-- morphi's ring with its last lines under Lately, and bubbles kept off the
-- toy bar, the ring and its caption.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local UI = require('src.ui')
local Chatter = require('src.chatter')
love.load()

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

TestChatterToy = {}

function TestChatterToy:setUp()
    Stub.width, Stub.height = 1280, 720
    love.resize(1280, 720)
    H.newGame('chatter', 1)
    H.closeGoal()
    H.setState('playing')
end

local function aliveWorker(game)
    for _, w in ipairs(game.workers) do
        if w.alive and not w:isBaby() then return w end
    end
end

function TestChatterToy:testTheToyBarHasAChatButton()
    lu.assertTrue(UI.RADIAL)
    H.drawScene()
    local ui = H.ui()
    local found
    for _, b in ipairs(ui.topButtons) do
        if b.id == 'chat' then found = b end
    end
    lu.assertNotNil(found, 'no CHAT button on the toy bar')
    lu.assertEquals(ui:toyButtonAt(found.x + 4, found.y + 4), 'chat')
end

function TestChatterToy:testTheChatButtonOpensThePanelAndClearsTheBadge()
    local game = H.game()
    local w = aliveWorker(game)
    for i = 1, 3 do w:say('berries ' .. i, 3) end
    lu.assertEquals(game.chatter:badge(), '3')
    H.pressToy('chat')
    lu.assertTrue(game.chatterOpen)
    lu.assertNil(game.chatter:badge())
    -- the panel is drawn and sits under the toy bar
    H.drawScene()
    local ui = H.ui()
    lu.assertNotNil(ui.chatterPanel, 'the panel was not drawn')
    lu.assertTrue(ui.chatterPanel.y >= ui.toyTopBottom, 'the panel covers the toy bar')
    H.pressToy('chat')
    lu.assertFalse(game.chatterOpen)
end

function TestChatterToy:testTappingALineOpensThatMorphisRingWithLately()
    local game = H.game()
    local w = aliveWorker(game)
    w:say('is that a shiny?', 3)
    w:say('wheee', 3)
    local e = game.chatter.lines[#game.chatter.lines]
    lu.assertEquals(e.speaker, w)
    H.chatterJump(e)
    local hud = H.hud()
    lu.assertTrue(hud:isOpen(), 'no ring opened')
    lu.assertEquals(game.selectedWorker, w)
    local said = hud.caption and hud.caption.said
    lu.assertNotNil(said, 'no Lately box in the caption')
    lu.assertStrContains(said, 'Lately')
    lu.assertStrContains(said, '"is that a shiny?"')
    lu.assertStrContains(said, '"wheee"')
end

function TestChatterToy:testAMorphiWithNothingSaidHasNoLately()
    local game = H.game()
    game.chatter = Chatter.new()
    local w = aliveWorker(game)
    H.openWorkerRing(w)
    lu.assertNil(H.hud().caption.said)
end

-- Every bubble stays clear of the toy bar, an open ring and its caption.
function TestChatterToy:testBubblesKeepClearOfTheRingAndBar()
    local game = H.game()
    local w = aliveWorker(game)
    H.openWorkerRing(w)
    H.drawScene() -- lays out the toy bar and the caption
    local hud, ui = H.hud(), H.ui()
    local clear = hud:keepClear(game)
    lu.assertTrue(#clear >= 2, 'the ring and caption give no keep-clear rects')
    local placed = {}
    local place = Chatter.place
    Chatter.place = function(list, blocked, screen, gap)
        place(list, blocked, screen, gap)
        for _, b in ipairs(list) do placed[#placed + 1] = b end
    end
    for _, o in ipairs(game.workers) do if o.alive then o:say('sticks sticks sticks', 3) end end
    H.drawScene()
    Chatter.place = place
    lu.assertTrue(#placed > 0, 'no bubbles were placed')
    for _, b in ipairs(placed) do
        if not b.hidden then
            lu.assertTrue(b.y >= ui.toyTopBottom, 'a bubble is under the toy bar')
            for _, r in ipairs(clear) do lu.assertFalse(overlaps(b, r), 'a bubble covers the ring or caption') end
        end
    end
end

-- Micah: "i can't scroll down in the chatter". A full log scrolls with the
-- wheel and by dragging the list; a drag never counts as a tap on a row, and
-- a plain tap on a row still goes to that morphi.
local function fillLog(game, w)
    for i = 1, 40 do
        game.chatter:add(w, 'berry number ' .. i, 'in the meadow', i)
    end
end

local function firstRowText(ui)
    local top
    for _, row in ipairs(ui.chatterRows) do
        if not top or row.y < top.y then top = row end
    end
    return top.entry.text
end

function TestChatterToy:testTheWheelScrollsChatterBack()
    local game = H.game()
    fillLog(game, aliveWorker(game))
    H.pressToy('chat')
    H.drawScene()
    local ui = H.ui()
    lu.assertTrue(#ui.chatterRows < #game.chatter.lines, 'everything fits: nothing to scroll')
    lu.assertNotNil(ui.chatterBar, 'no scroll bar on a full log')
    local newest = ui.chatterRows[1].entry.text
    lu.assertEquals(newest, 'berry number 40')
    local r = ui.chatterPanel
    local get = love.mouse.getPosition
    love.mouse.getPosition = function() return (r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale end
    local zoom = game.camera.scale
    for _ = 1, 5 do love.wheelmoved(0, 1) end
    love.mouse.getPosition = get
    lu.assertEquals(game.chatter.scroll, 5)
    lu.assertEquals(game.camera.scale, zoom, 'the wheel over Chatter zoomed the map')
    H.drawScene()
    lu.assertEquals(ui.chatterRows[1].entry.text, 'berry number 35')
    -- all the way back: the oldest line shows and it stops there
    for _ = 1, 80 do game.chatter:scrollBy(1); H.drawScene() end
    lu.assertEquals(firstRowText(ui), game.chatter.lines[1].text)
    local most = game.chatter.scroll
    game.chatter:scrollBy(1)
    lu.assertEquals(game.chatter.scroll, most)
    -- closing and opening again starts at the newest
    H.pressToy('chat'); H.pressToy('chat')
    lu.assertEquals(game.chatter.scroll, 0)
end

function TestChatterToy:testDraggingScrollsAndATapStillJumps()
    local game = H.game()
    local w = aliveWorker(game)
    fillLog(game, w)
    H.pressToy('chat')
    H.drawScene()
    local ui = H.ui()
    local s = ui.scale
    local row = ui.chatterRows[2]
    local x, y = (row.x + row.w / 2) * s, (row.y + row.h / 2) * s
    -- drag down by three rows: older lines come into view, no ring opens
    love.mousepressed(x, y, 1, false)
    love.mousemoved(x, y + 3 * 56 * s, 0, 3 * 56 * s, false)
    love.mousereleased(x, y + 3 * 56 * s, 1, false)
    lu.assertEquals(game.chatter.scroll, 3)
    lu.assertFalse(H.hud():isOpen(), 'a drag opened a ring')
    lu.assertTrue(game.chatterOpen)
    -- a tap on a row goes to whoever said it
    H.drawScene()
    row = ui.chatterRows[1]
    x, y = (row.x + row.w / 2) * s, (row.y + row.h / 2) * s
    love.mousepressed(x, y, 1, false)
    love.mousereleased(x, y, 1, false)
    lu.assertEquals(game.selectedWorker, w)
    lu.assertTrue(H.hud():isOpen(), 'a tap on a row opened no ring')
end

os.exit(lu.LuaUnit.run())
