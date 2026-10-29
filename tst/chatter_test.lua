local lu = require('libs.luaunit')
require('src.constants')
local Chatter = require('src.chatter')

TestChatter = {}

local function width(s) return #s * 8 end

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- The log keeps the newest 60 lines in the order they were said.
function TestChatter:testLogKeepsTheNewestInOrder()
    local c = Chatter.new()
    local pip = { name = 'Pip' }
    for i = 1, 75 do c:add(pip, 'line ' .. i, 'in the meadow', i) end
    lu.assertEquals(#c.lines, Chatter.KEEP)
    lu.assertEquals(c.lines[1].text, 'line 16')
    lu.assertEquals(c.lines[#c.lines].text, 'line 75')
    lu.assertEquals(c.lines[#c.lines].name, 'Pip')
end

-- Unread counts lines said while the panel is shut; opening it clears them.
function TestChatter:testBadgeCountsUnread()
    local c = Chatter.new()
    local pip = { name = 'Pip' }
    lu.assertNil(c:badge())
    c:seed({ 'Pip', 'Mo' }, 0)
    lu.assertNil(c:badge()) -- the starting lines are not news
    for i = 1, 3 do c:add(pip, 'hi', nil, i) end
    lu.assertEquals(c:badge(), '3')
    for i = 1, 10 do c:add(pip, 'hi', nil, i) end
    lu.assertEquals(c:badge(), '9+')
    c:setOpen(true)
    lu.assertNil(c:badge())
    c:add(pip, 'while open', nil, 20)
    lu.assertNil(c:badge())
    c:setOpen(false)
    c:add(pip, 'shut again', nil, 21)
    lu.assertEquals(c:badge(), '1')
end

-- Lately: one morphi's last two lines, oldest first.
function TestChatter:testLatelyIsOneSpeakersLastLines()
    local c = Chatter.new()
    local pip, mo = { name = 'Pip' }, { name = 'Mo' }
    c:add(pip, 'one', nil, 1)
    c:add(mo, 'not mine', nil, 2)
    c:add(pip, 'two', nil, 3)
    c:add(pip, 'three', nil, 4)
    lu.assertEquals(c:lately(pip, 2), { 'two', 'three' })
    lu.assertEquals(c:lately(mo, 2), { 'not mine' })
    lu.assertEquals(c:lately({ name = 'Nobody' }, 2), {})
end

function TestChatter:testAgo()
    lu.assertEquals(Chatter.ago(3), 'just now')
    lu.assertEquals(Chatter.ago(27), '20 s ago')
    lu.assertEquals(Chatter.ago(130), '2 min ago')
end

-- Wrapping never makes more than 3 lines, nor a line wider than the plate,
-- even with one word longer than a line.
function TestChatter:testWrapStaysInsideThePlate()
    local texts = {
        'hi',
        'is that a shiny over there by the stream?',
        'I would like a very long nap in a very soft nest please and then some berries and then another nap',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '',
    }
    for _, t in ipairs(texts) do
        local lines = Chatter.wrap(t, 120, width)
        lu.assertTrue(#lines >= 1 and #lines <= 3, t)
        for _, l in ipairs(lines) do lu.assertTrue(width(l) <= 120, l) end
    end
    local long = Chatter.wrap(texts[3], 120, width)
    lu.assertEquals(#long, 3)
    lu.assertStrContains(long[3], '..')
    lu.assertEquals(Chatter.wrap('berries!', 120, width), { 'berries!' })
end

-- A crowd of twelve talking at once: no two shown bubbles overlap, all
-- stay on screen and off the open panel, and of a pair standing together
-- only the newer one shows.
function TestChatter:testPlacementInACrowd()
    local screen = { x = 0, y = 40, w = 800, h = 500 }
    local panel = { x = 520, y = 40, w = 280, h = 500 }
    local bubbles = {}
    for i = 1, 12 do
        local sx, sy = 60 + (i % 6) * 70, 120 + math.floor(i / 6) * 150
        bubbles[#bubbles + 1] = { sx = sx, sy = sy, w = 120, h = 40, t = i, id = i }
    end
    -- a pair talking: 23 says something after 24, both standing together
    bubbles[#bubbles + 1] = { sx = 300, sy = 420, w = 100, h = 30, t = 50, id = 23 }
    bubbles[#bubbles + 1] = { sx = 306, sy = 423, w = 100, h = 30, t = 40, id = 24 }
    Chatter.place(bubbles, { panel }, screen, 20)
    local shown, byId = {}, {}
    for _, b in ipairs(bubbles) do
        byId[b.id] = b
        if not b.hidden then shown[#shown + 1] = b end
    end
    lu.assertTrue(#shown >= 8)
    for i, a in ipairs(shown) do
        lu.assertTrue(a.x >= screen.x and a.y >= screen.y and a.x + a.w <= screen.x + screen.w and a.y + a.h <= screen.y + screen.h)
        lu.assertFalse(overlaps(a, panel), 'bubble ' .. a.id .. ' under the panel')
        for j = i + 1, #shown do lu.assertFalse(overlaps(a, shown[j]), a.id .. ' overlaps ' .. shown[j].id) end
    end
    lu.assertFalse(byId[23].hidden)
    lu.assertTrue(byId[24].hidden)
end

-- A bubble at the top of the screen flips below its speaker.
function TestChatter:testBubbleAtTheTopGoesBelow()
    local b = { sx = 200, sy = 50, w = 120, h = 40, t = 1 }
    Chatter.place({ b }, {}, { x = 0, y = 40, w = 800, h = 500 }, 20)
    lu.assertFalse(b.hidden)
    lu.assertTrue(b.below)
    lu.assertTrue(b.y > b.sy)
end

os.exit(lu.LuaUnit.run())
