-- The hunting party through the real main loop: offered on day 8, picked,
-- sent out, and home again with meat (or empty-handed on the way back).
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()
love.resize(1280, 720)

local function offered()
    H.newGame('PUPPER', 1)
    local g = H.game()
    H.closeGoal()
    g.scoring.quarterTimer = QUARTER_SECONDS - DAY_SECONDS * (HUNT_LEAVE_DAY - 1) - 1
    for _ = 1, 20 do
        love.update(0.1)
        if H.state() == 'huntpick' then break end
    end
    return g
end

TestHuntFlow = {}

function TestHuntFlow:test_day_eight_offers_the_party_and_not_now_stays_home()
    local g = offered()
    lu.assertEquals(H.state(), 'huntpick')
    love.draw()
    love.keypressed('escape')
    lu.assertEquals(H.state(), 'playing')
    lu.assertEquals(H.game(), g)
end

function TestHuntFlow:test_a_party_hunts_and_brings_meat_home()
    local g = offered()
    local br = g.world.breakroom
    for dx = 1, 6 do g.world:markStorage(br.x + dx, br.y + 1) end
    love.draw()
    love.keypressed('return')
    lu.assertEquals(H.state(), 'playing')
    local h = H.game()
    lu.assertEquals(h.mode, 'hunt')
    lu.assertTrue(#h.workers >= 1)
    love.draw()
    for _ = 1, 4000 do
        love.update(0.1)
        if H.game() ~= h then break end
    end
    lu.assertEquals(H.game(), g)
    lu.assertEquals(g.mode, 'free')
    local last = g.log[#g.log] and g.log[#g.log].text or ''
    lu.assertNotNil(last:find('hunting party is home with [1-9]'), last)
end

function TestHuntFlow:test_quitting_a_hunt_comes_home_empty_handed()
    local g = offered()
    love.keypressed('return')
    lu.assertEquals(H.game().mode, 'hunt')
    H.goToTitle()
    lu.assertEquals(H.game(), g)
    lu.assertEquals(H.state(), 'playing')
end

os.exit(lu.LuaUnit.run())
