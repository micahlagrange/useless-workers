-- Babies (epic hatchlings): free play starts with one, Morphi; a baby does
-- no work, eats and naps, its needs run down, and it grows up after
-- BABY_SECONDS, dealt jobs, its mood set by how well it was cared for.
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

local function baby(g)
    for _, w in ipairs(g.workers) do if w:isBaby() then return w end end
end

TestBabies = {}

function TestBabies:test_free_play_starts_with_three_grown_ups_and_morphi()
    H.newGame('PUPPER', 1)
    local g = H.game()
    local grown, babies = 0, 0
    for _, w in ipairs(g.workers) do
        if w:isBaby() then babies = babies + 1 else grown = grown + 1 end
    end
    lu.assertEquals({ grown, babies }, { 3, 1 })
    local b = baby(g)
    lu.assertEquals(b.name, 'Morphi')
    lu.assertFalse(b:isWorking(), 'a baby is not one of the workers')
    lu.assertNil(b.jobSet)
    lu.assertEquals(b.roleInfo.label, 'Baby')
    -- in the home nest
    local t = b:tile()
    lu.assertTrue(math.abs(t.x - g.world.breakroom.x) <= 1 and math.abs(t.y - g.world.breakroom.y) <= 1)
end

function TestBabies:test_a_baby_does_no_work_stays_near_home_and_its_needs_run_down()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local b = baby(g)
    local home = g.world.breakroom
    local far = 0
    for _ = 1, 600 do
        love.update(0.1)
        lu.assertNil(b.job, 'a baby never takes a job')
        local t = b:tile()
        far = math.max(far, math.abs(t.x - home.x) + math.abs(t.y - home.y))
    end
    lu.assertTrue(far <= BABY_WANDER * 2 + 2, 'a baby toddles about near home, got ' .. far .. ' away')
    lu.assertTrue(b.needs.fun < 100 and b.needs.clean < 100, 'its needs run down')
    lu.assertTrue(b.age >= 59)
    lu.assertTrue(b:babySummary():find('grows up in') ~= nil)
end

function TestBabies:test_a_baby_grows_up_after_a_season_and_is_dealt_jobs()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local b = baby(g)
    b.age = BABY_SECONDS - 0.5
    for _ = 1, 20 do love.update(0.1) end
    lu.assertFalse(b:isBaby())
    lu.assertTrue(b:isWorking())
    lu.assertNotNil(b.jobSet)
    lu.assertEquals(b.role, b.jobSet.main)
    lu.assertTrue(b.morale >= BABY_MORALE_MIN)
    local grew = false
    for _, e in ipairs(g.log) do if e.text:find('grew up') then grew = true end end
    lu.assertTrue(grew, 'the log says it grew up')
end

function TestBabies:test_care_sets_its_mood_when_it_grows_up()
    H.newGame('PUPPER', 1)
    local g = H.game()
    local b = baby(g)
    -- neglected: every need empty its whole babyhood
    b.needs = { fun = 0, clean = 0, sleep = 0 }
    b.hunger = 0
    b.careSum, b.careTime = 0, 100
    b:growUp({ main = ROLE_FORAGER, neutral = ROLE_HUNTER, disliked = ROLE_MINER })
    lu.assertEquals(b.morale, BABY_MORALE_MIN)
    -- well loved
    H.newGame('PUPPER', 1)
    b = baby(H.game())
    b.careSum, b.careTime = 95 * 100, 100
    b:growUp({ main = ROLE_FORAGER, neutral = ROLE_HUNTER, disliked = ROLE_MINER })
    lu.assertEquals(b.morale, 95)
end

os.exit(lu.LuaUnit.run())
