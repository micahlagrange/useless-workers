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
local Hunt = require('src.hunt')
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
    -- they left on day 8 and are back for the season's last day
    lu.assertEquals(Hunt.seasonDay(g.scoring.quarterTimer), DAYS_PER_SEASON)
end

function TestHuntFlow:test_once_a_season_no_second_offer_after_not_now()
    local g = offered()
    love.keypressed('escape')
    for _ = 1, 50 do love.update(0.1) end
    lu.assertEquals(H.state(), 'playing')
    lu.assertEquals(g.huntOffered, g.scoring.quarter)
end

function TestHuntFlow:test_the_party_is_at_most_three_picked_morphis()
    local g = offered()
    local pick = H.huntPick()
    lu.assertTrue(pick.max <= HUNT_PARTY_SIZE)
    lu.assertTrue(#pick.chosen <= pick.max)
    -- toggling the first off and on again keeps the party picked by hand
    local first = pick.candidates[1].name
    love.keypressed('1')
    local had = false
    for _, n in ipairs(pick.chosen) do if n == first then had = true end end
    love.keypressed('1')
    local has = false
    for _, n in ipairs(pick.chosen) do if n == first then has = true end end
    lu.assertNotEquals(had, has)
    love.keypressed('return')
    local h = H.game()
    lu.assertEquals(h.mode, 'hunt')
    lu.assertTrue(#h.workers <= HUNT_PARTY_SIZE)
    for _, w in ipairs(h.workers) do
        local picked = false
        for _, n in ipairs(pick.chosen) do if n == w.name then picked = true end end
        lu.assertTrue(picked, w.name)
    end
    H.goToTitle()
    lu.assertEquals(H.game(), g)
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
