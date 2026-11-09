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

local JobSets = require('src.jobsets')

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


TestCaretaker = {}

function TestCaretaker:test_the_deal_covers_all_six_jobs()
    lu.assertEquals(#JobSets.JOBS, 6)
    for seed = 1, 1000 do
        local sets = JobSets.dealStart(JobSets.rngFor(seed), 3)
        lu.assertTrue(JobSets.covered(sets), 'seed ' .. seed)
    end
end

function TestCaretaker:test_a_caretaker_visits_a_baby_that_needs_it()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local b = baby(g)
    -- one grown-up minds babies first; a stash of berries nearby
    local carer = g.workers[1]
    carer:setJob('main', ROLE_CARETAKER)
    b.needs.fun, b.needs.clean = 10, 10
    b.hunger = 50
    g.world.stock.grass = 3
    local visited = false
    for _ = 1, 600 do
        love.update(0.1)
        if b.needs.fun > 40 then visited = true break end
    end
    lu.assertTrue(visited, 'the caretaker played with the baby')
    lu.assertTrue(b.needs.clean > 40, 'and washed it, with a tuft of grass')
    lu.assertEquals(g.world.stock.grass, 2)
end

function TestCaretaker:test_a_baby_knows_when_someone_minds_babies()
    H.newGame('PUPPER', 1)
    local g = H.game()
    local b = baby(g)
    g.workers[1]:setJob('main', ROLE_CARETAKER)
    lu.assertTrue(b:hasCaretaker())
end


TestEggs = {}

local function seasonChange()
    -- to the end of the season, then on from the report
    local g = H.game()
    g.scoring.quarterTimer = 0.05
    for _ = 1, 5 do
        love.update(0.1)
        if H.state() == 'huntpick' then love.keypressed('escape') end
        if H.state() == 'report' then break end
    end
    lu.assertEquals(H.state(), 'report')
    love.keypressed('return')
end

local function eggs(g)
    local out = {}
    for _, w in ipairs(g.workers) do if w.alive and w:isEgg() then out[#out + 1] = w end end
    return out
end

function TestEggs:test_no_free_nest_no_egg()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local n = #g.workers
    seasonChange()
    -- Morphi has the home nest and nobody has woven a nest yet
    lu.assertEquals(#eggs(g), 0)
    lu.assertEquals(#g.workers, n, 'nobody wandered in: no migrants any more')
    local said = false
    for _, e in ipairs(g.log) do if e.text:find('Weave a NEST') then said = true end end
    lu.assertTrue(said, 'the season line says to weave a nest')
end

function TestEggs:test_a_pair_lays_an_egg_in_a_free_nest_and_it_hatches()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    -- one woven nest
    local br = g.world.breakroom
    local spot
    for dx = -4, 4 do for dy = -4, 4 do
        local x, y = br.x + dx, br.y + dy
        if not spot and g.world:canSite(SITE_BED, x, y) then spot = { x = x, y = y } end
    end end
    g.world:markBed(spot.x, spot.y)
    seasonChange()
    local laid = eggs(g)
    lu.assertEquals(#laid, 1, 'one free nest, one egg')
    local egg = laid[1]
    lu.assertEquals({ egg.nest.x, egg.nest.y }, { spot.x, spot.y })
    lu.assertEquals(#egg.parents, 2)
    local sheets = {}
    for _, w in ipairs(g.workers) do if w.name == egg.parents[1] or w.name == egg.parents[2] then sheets[w.sheet] = true end end
    lu.assertTrue(sheets[egg.sheet], 'the egg takes the looks of a parent')
    lu.assertFalse(egg:isWorking())
    for _ = 1, math.floor((EGG_HATCH_SECONDS + 1) / 0.1) do love.update(0.1) end
    lu.assertTrue(egg:isBaby(), 'it hatched into a baby')
    local said = false
    for _, e in ipairs(g.log) do if e.text:find('hatched') then said = true end end
    lu.assertTrue(said)
end


TestDanger = {}

function TestDanger:test_a_hungry_baby_is_warned_about_then_dies()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local b = baby(g)
    -- nothing to eat anywhere, nobody minding babies
    for i = #g.world.items, 1, -1 do table.remove(g.world.items, i) end
    for _, n in ipairs(g.world.nodes) do n.ready = false; n.timer = 9999 end
    for _, w in ipairs(g.workers) do w.slots = {} end
    b.hunger = 0
    local warned, warnedAt = false, nil
    for step = 1, math.floor((BABY_STARVE_SECONDS + 2) / 0.1) do
        b.hunger = 0
        love.update(0.1)
        if not warned then
            for _, e in ipairs(g.log) do if e.text:find('hungry baby') then warned = true; warnedAt = step * 0.1 end end
        end
        if not b.alive then break end
    end
    lu.assertTrue(warned, 'a warning first')
    lu.assertTrue(warnedAt < BABY_STARVE_SECONDS)
    lu.assertFalse(b.alive, 'then it is gone')
    lu.assertEquals(#g.world.graves, 1)
    local said = false
    for _, e in ipairs(g.log) do if e.text:find('is gone') then said = true end end
    lu.assertTrue(said)
end

function TestDanger:test_a_starving_grown_up_dies_in_free_play()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local w = g.workers[1]
    w.hunger = 0
    w.starveTimer = 0.05
    love.update(0.1)
    lu.assertFalse(w.alive)
    lu.assertNotEquals(w.state, 'quitting', 'gone, not wandering off')
    local died = 0
    for _, e in ipairs(g.stats.events) do if e.kind == 'died' then died = died + 1 end end
    lu.assertEquals(died, 1)
end

function TestDanger:test_an_egg_never_dies()
    H.newGame('PUPPER', 1)
    local g = H.game()
    local egg = H.game().workers[1] -- borrow the first worker's slot to make an egg
    egg.stage, egg.hatchTimer, egg.hunger = 'egg', 9999, 0
    for _ = 1, 100 do egg:update(1, 0) end
    lu.assertTrue(egg.alive)
end

os.exit(lu.LuaUnit.run())
