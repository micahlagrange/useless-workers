-- Paused play (Micah's review of epic-chatter): a NEXT unit button that opens
-- the ring and follows, a pause pill that is small, and little blobs that are
-- easier to hit.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()

TestNextUnitToy = {}

function TestNextUnitToy:setUp()
    Stub.width, Stub.height = 1280, 720
    love.resize(1280, 720)
    H.newGame('nextunit', 1)
    H.closeGoal()
    H.setState('playing')
end

local function button(id)
    H.drawScene()
    for _, b in ipairs(H.ui().topButtons) do if b.id == id then return b end end
end

function TestNextUnitToy:testTheBarHasANextUnitButton()
    local b = button('nextunit')
    lu.assertNotNil(b)
    lu.assertEquals(H.ui():toyButtonAt(b.x + 4, b.y + 4), 'nextunit')
end

function TestNextUnitToy:testNextOpensTheRingAndFollowsEvenWhilePaused()
    local game = H.game()
    game.paused = true
    local seen = {}
    for _ = 1, 3 do
        H.pressToy('nextunit')
        lu.assertTrue(game.follow, 'not following')
        lu.assertTrue(H.hud():isOpen(), 'no ring')
        lu.assertNotNil(game.selectedWorker)
        seen[game.selectedWorker] = true
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    lu.assertTrue(n >= 2, 'next did not move on to another morphi')
end

function TestNextUnitToy:testThePausePillIsSmallAndCarriesOn()
    local game = H.game()
    game.paused = true
    local b = button('carryon')
    lu.assertNotNil(b)
    lu.assertTrue(b.h <= 40 and b.w <= 220, 'the pause pill is big: ' .. b.w .. 'x' .. b.h)
    H.pressToy('carryon')
    lu.assertFalse(game.paused)
end
