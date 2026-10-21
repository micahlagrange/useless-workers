-- Five-minute seasons and the three-morphi start (epic seasons-bench).
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Stats = require('src.stats')
love.load()
love.resize(1280, 720)

-- What came once a 90 s season, scaled to the new length.
local SCALE = QUARTER_SECONDS / 90
local function scaled(n) return math.floor(n * SCALE + 0.5) end

TestSeasons = {}

function TestSeasons:test_a_season_is_five_minutes_of_nine_days()
    lu.assertEquals(QUARTER_SECONDS, 300)
    lu.assertEquals(DAY_SECONDS, QUARTER_SECONDS / DAYS_PER_SEASON)
    lu.assertEquals(MILESTONE_GAP_DAYS, DAYS_PER_SEASON * 3)
end

function TestSeasons:test_per_season_growth_and_grades_follow_the_season_length()
    -- 4 / 2 / 3 new nodes and grades of 16 / 11 / 6 / 2 were set for 90 s
    lu.assertEquals({ NODES_PER_QUARTER.bush, NODES_PER_QUARTER.tree, NODES_PER_QUARTER.ore }, { scaled(4), scaled(2), scaled(3) })
    local was = { 16, 11, 6, 2 }
    for i, g in ipairs(GRADE_THRESHOLDS) do lu.assertEquals(g[2], scaled(was[i])) end
    -- the endless drain step and migrants are tuned with tools/bench.py; a
    -- longer season never brings fewer migrants than a 90 s one did
    lu.assertTrue(ENDLESS_DRAIN_STEP > 0 and ENDLESS_DRAIN_STEP < 0.1)
    local before = { 2, 3, 4 }
    for i, n in ipairs(MIGRANTS_PER_SEASON) do lu.assertTrue(n >= before[i]) end
end

function TestSeasons:test_the_season_clock_runs_a_full_season()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local game = H.game()
    lu.assertEquals(game.scoring.quarterTimer, QUARTER_SECONDS)
    -- half a season in, still the first season and on its middle day
    local dt = 1 / 10
    for _ = 1, math.floor(QUARTER_SECONDS / 2 / dt) do love.update(dt) end
    lu.assertEquals(H.state(), 'playing')
    lu.assertAlmostEquals(game.clock, QUARTER_SECONDS / 2, 0.5)
    lu.assertEquals(game.scoring.quarter, 1)
    lu.assertEquals(Stats.dayOf(game), math.floor(DAYS_PER_SEASON / 2) + 1)
end

function TestSeasons:test_free_play_starts_with_the_offered_wilds_band()
    lu.assertEquals(DIFFICULTIES[1].workers, 3)
    H.newGame('PUPPER', 1)
    local game = H.game()
    lu.assertEquals(#game.workers, DIFFICULTIES[1].workers)
    -- the species come round in the old hire order's looks; the jobs are
    -- dealt (tst/jobs_test.lua checks how), the role is the main job
    for i, w in ipairs(game.workers) do
        lu.assertEquals(w.sheet, HIRE_SHEETS[(i - 1) % #HIRE_SHEETS + 1])
        lu.assertNotNil(w.jobSet)
        lu.assertEquals(w.role, w.jobSet.main)
    end
    -- the other wilds keep their own numbers
    lu.assertEquals(DIFFICULTIES[2].workers, 4)
    lu.assertEquals(DIFFICULTIES[3].workers, 3)
    lu.assertEquals(DIFFICULTIES[4].workers, 2)
    -- any band size works
    H.newGame('PUPPER', 2)
    game = H.game()
    lu.assertEquals(#game.workers, DIFFICULTIES[2].workers)
    lu.assertEquals(game.workers[4].sheet, HIRE_SHEETS[4])
end

function TestSeasons:test_a_survival_level_counts_days_from_its_start_not_by_season()
    H.newLevel(1, 'survival', 1)
    H.closeGoal()
    local game = H.game()
    lu.assertTrue(game.scoring.quarterTimer < QUARTER_SECONDS)
    game.clock = DAY_SECONDS * 2 + 1
    lu.assertEquals(Stats.dayOf(game), 3)
end

os.exit(lu.LuaUnit.run())
