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

os.exit(lu.LuaUnit.run())
