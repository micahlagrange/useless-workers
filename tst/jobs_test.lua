-- Player-assigned jobs (epic player-jobs): the deal, the order a morphi
-- works its three jobs in, what the player may change, and that free play's
-- jobs leave arcade and old seeds alone.
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')
local JobSets = require('src.jobsets')
love.load()
love.resize(1280, 720)

local function threeDifferent(s)
    return s.main and s.disliked and s.main ~= s.disliked
        and s.neutral ~= s.main and s.neutral ~= s.disliked
end

local function count(list, v)
    local n = 0
    for _, x in ipairs(list) do if x == v then n = n + 1 end end
    return n
end

TestDeal = {}

function TestDeal:test_the_start_follows_the_rules_for_any_band_size()
    for n = 1, 9 do
        for seed = 1, 60 do
            local sets = JobSets.dealStart(JobSets.rngFor(seed), n)
            lu.assertEquals(#sets, n)
            local mains, dislikes = {}, {}
            for _, s in ipairs(sets) do
                lu.assertTrue(threeDifferent(s), 'a morphi has three different jobs')
                lu.assertNotNil(s.neutral, 'the start deals a neutral job to everyone')
                mains[#mains + 1] = s.main
                dislikes[#dislikes + 1] = s.disliked
            end
            -- unique while there are jobs enough; beyond four, as even as can be
            local most = math.ceil(n / #JobSets.JOBS)
            for _, job in ipairs(JobSets.JOBS) do
                lu.assertTrue(count(mains, job) <= most, 'mains are unique')
                lu.assertTrue(count(dislikes, job) <= most, 'dislikes are unique')
            end
            -- a band of two or more always covers all four jobs somewhere
            if n >= 2 then lu.assertTrue(JobSets.covered(sets), 'all four jobs covered, n=' .. n .. ' seed=' .. seed) end
        end
    end
end

function TestDeal:test_the_deal_is_random_but_repeats_for_a_seed()
    lu.assertEquals(JobSets.dealStart(JobSets.rngFor(42), 3), JobSets.dealStart(JobSets.rngFor(42), 3))
    -- different seeds give different starts: no static list of beginning jobs
    local seen = {}
    for seed = 1, 40 do
        local s = JobSets.dealStart(JobSets.rngFor(seed), 3)
        seen[s[1].main .. s[2].main .. s[3].main] = true
    end
    local kinds = 0
    for _ in pairs(seen) do kinds = kinds + 1 end
    lu.assertTrue(kinds >= 6, 'starts vary from seed to seed')
    -- builder is somebody's main job in some starts
    local builderMain = false
    for seed = 1, 40 do
        for _, s in ipairs(JobSets.dealStart(JobSets.rngFor(seed), 3)) do
            if s.main == ROLE_BUILDER then builderMain = true end
        end
    end
    lu.assertTrue(builderMain)
end

function TestDeal:test_an_immigrant_favours_the_jobs_the_band_lacks()
    local band = {
        { main = ROLE_FORAGER, neutral = ROLE_MINER, disliked = ROLE_LUMBERJACK },
        { main = ROLE_MINER, neutral = ROLE_FORAGER, disliked = ROLE_LUMBERJACK },
        { main = ROLE_HUNTER, neutral = ROLE_FORAGER, disliked = ROLE_MINER },
    }
    for seed = 1, 30 do
        local s = JobSets.dealOne(Rng.new(seed), band)
        lu.assertTrue(threeDifferent(s))
        lu.assertEquals(s.main, ROLE_BUILDER, 'nobody has builder: the immigrant does')
    end
    -- with every job covered, the immigrant still has three different jobs
    -- and takes a main nobody has as main when there is one
    band[4] = { main = ROLE_BUILDER, neutral = ROLE_FORAGER, disliked = ROLE_MINER }
    for seed = 1, 30 do
        local s = JobSets.dealOne(Rng.new(seed), band)
        lu.assertTrue(threeDifferent(s))
        lu.assertEquals(s.main, ROLE_LUMBERJACK)
    end
end

function TestDeal:test_a_separate_stream_leaves_old_seeds_unchanged()
    -- the deal rolls JobSets.rngFor, never the game's stream: deal from a
    -- different stream and the game's random state and map are the same
    local function snapshot(seed, d)
        H.newGame(seed, d)
        local g = H.game()
        local h = 0
        for y = 1, g.world.h do
            for x = 1, g.world.w do
                local t = g.world:get(x, y)
                local s = (t.type or '') .. (t.node and t.node.kind or '')
                for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
            end
        end
        local sheets, jobs = {}, {}
        for _, w in ipairs(g.workers) do sheets[#sheets + 1] = w.sheet; jobs[#jobs + 1] = w.jobSet.main end
        return g.rng.state, h, table.concat(sheets, ','), table.concat(jobs, ',')
    end
    local real = JobSets.rngFor
    for _, case in ipairs({ { 'PUPPER', 1 }, { '12345', 1 }, { 'BANANAS', 2 } }) do
        local s1, h1, sh1, j1 = snapshot(case[1], case[2])
        JobSets.rngFor = function(n) return real((n or 1) + 99991) end
        local s2, h2, sh2, j2 = snapshot(case[1], case[2])
        JobSets.rngFor = real
        lu.assertEquals(s2, s1, case[1] .. ' rng')
        lu.assertEquals(h2, h1, case[1] .. ' map')
        lu.assertEquals(sh2, sh1, case[1] .. ' looks')
    end
    -- the species still come round in the old order: looks and tastes as before
    H.newGame('PUPPER', 1)
    local sheets = { 'pupper', 'twins', 'cwab' }
    for i, w in ipairs(H.game().workers) do lu.assertEquals(w.sheet, sheets[i]) end
end

function TestDeal:test_free_play_deals_jobs_and_immigrants_get_them_too()
    H.newGame('PUPPER', 1)
    local g = H.game()
    local sets = {}
    for _, w in ipairs(g.workers) do
        lu.assertNotNil(w.jobSet)
        lu.assertEquals(w.role, w.jobSet.main)
        lu.assertTrue(threeDifferent(w.jobSet))
        sets[#sets + 1] = w.jobSet
    end
    lu.assertTrue(JobSets.covered(sets))
    H.closeGoal()
    -- run past the first change of season: the migrants come with jobs
    local n = #g.workers
    for _ = 1, math.floor((QUARTER_SECONDS + 2) / 0.1) do love.update(0.1) end
    if #g.workers > n then
        for i = n + 1, #g.workers do
            lu.assertNotNil(g.workers[i].jobSet)
            lu.assertTrue(threeDifferent(g.workers[i].jobSet))
        end
    end
end

TestJobRules = {}

function TestJobRules:test_the_disliked_job_cannot_be_changed()
    local s = { main = ROLE_FORAGER, neutral = ROLE_MINER, disliked = ROLE_BUILDER }
    local ok = JobSets.set(s, 'disliked', ROLE_LUMBERJACK)
    lu.assertFalse(ok)
    lu.assertEquals(s.disliked, ROLE_BUILDER)
    -- nor can it be the neutral job
    lu.assertFalse((JobSets.set(s, 'neutral', ROLE_BUILDER)))
    lu.assertEquals(s, { main = ROLE_FORAGER, neutral = ROLE_MINER, disliked = ROLE_BUILDER })
end

function TestJobRules:test_the_disliked_job_can_be_made_the_main_job()
    local s = { main = ROLE_FORAGER, neutral = ROLE_MINER, disliked = ROLE_BUILDER }
    lu.assertTrue((JobSets.set(s, 'main', ROLE_BUILDER)))
    lu.assertEquals(s, { main = ROLE_BUILDER, neutral = ROLE_MINER, disliked = ROLE_BUILDER })
    -- it is tried once, as the main job
    local order = JobSets.order(s)
    lu.assertEquals(#order, 2)
    lu.assertEquals(order[1], { job = ROLE_BUILDER, slot = 'main' })
    lu.assertEquals(order[2], { job = ROLE_MINER, slot = 'neutral' })
    -- the neutral job back as main: the disliked one does not become the fallback
    lu.assertTrue((JobSets.set(s, 'main', ROLE_MINER)))
    lu.assertEquals(s, { main = ROLE_MINER, disliked = ROLE_BUILDER })
end

function TestJobRules:test_the_player_changes_main_and_neutral()
    local s = { main = ROLE_FORAGER, neutral = ROLE_MINER, disliked = ROLE_BUILDER }
    lu.assertTrue((JobSets.set(s, 'main', ROLE_LUMBERJACK)))
    lu.assertEquals(s.main, ROLE_LUMBERJACK)
    lu.assertEquals(s.neutral, ROLE_MINER)
    -- the neutral job made main swaps the two, so nothing is lost
    lu.assertTrue((JobSets.set(s, 'main', ROLE_MINER)))
    lu.assertEquals(s.main, ROLE_MINER)
    lu.assertEquals(s.neutral, ROLE_LUMBERJACK)
    -- the neutral job can be emptied; the main one cannot
    lu.assertTrue((JobSets.set(s, 'neutral', nil)))
    lu.assertNil(s.neutral)
    lu.assertFalse((JobSets.set(s, 'main', nil)))
    lu.assertFalse((JobSets.set(s, 'neutral', ROLE_MINER)), 'neutral cannot be the main job')
end

-- b: ripe bush (2,2)  T: tree (9,2)  S: storage
local GRID = {
    '..........',
    '.b......T.',
    '..........',
    '...SBBS...',
    '...SBBS...',
    '..........',
}

local function run(workers, world, jobs, seconds)
    local dt, clock = 0.05, 0
    for _ = 1, math.floor(seconds / dt) do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, function(n) jobs:postNode(n) end)
        for _, w in ipairs(workers) do w:update(dt, clock) end
    end
end

TestJobOrder = {}

function TestJobOrder:setUp()
    self.world = World.fromGrid(GRID, Rng.new(1))
    self.jobs = Jobs.new()
    self.scoring = Scoring.new(1)
    self.bush = self.world:get(2, 2).node
    self.tree = self.world:get(9, 2).node
    for _, n in ipairs(self.world.nodes) do n.food = 'steak' end
    self.make = function(jobs, x)
        return Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), {
            x = x or 5, y = 3, jobs = jobs, name = 'Dave', drain = 0.5, diet = 'steak', wilds = true, sheet = 'pupper',
        })
    end
end

-- the first job it takes, as the job of the task in hand
local function firstJob(w, workers, world, jobs)
    for _ = 1, 100 do
        run(workers, world, jobs, 0.1)
        if w.doing then return w.doing end
    end
    return nil
end

function TestJobOrder:test_a_hunter_catches_a_critter_and_brings_meat_home()
    self.bush.ready = false; self.bush.timer = 999
    local critter = self.world:addNode(NODE_CRITTER, 9, 5)
    critter.hopTimer = 999 -- sit still for the test
    self.jobs:postNode(critter)
    local w = self.make({ main = ROLE_HUNTER, neutral = ROLE_FORAGER, disliked = ROLE_MINER })
    lu.assertEquals(firstJob(w, { w }, self.world, self.jobs), ROLE_HUNTER)
    run({ w }, self.world, self.jobs, 20)
    lu.assertEquals(self.world:storedCount(ITEM_FOOD), 1)
    local item = self.world.items[1]
    lu.assertEquals(item.food, MEAT)
    lu.assertEquals(#self.world:nodesOfKind(NODE_CRITTER), 0)
end

function TestJobOrder:test_main_beats_neutral_beats_disliked()
    self.jobs:postNode(self.bush)
    self.jobs:postNode(self.tree)
    local w = self.make({ main = ROLE_LUMBERJACK, neutral = ROLE_FORAGER, disliked = ROLE_MINER }, 3)
    -- the bush is nearer, but gathering sticks is its main job
    lu.assertEquals(firstJob(w, { w }, self.world, self.jobs), ROLE_LUMBERJACK)
    lu.assertEquals(w:describeState():find('neutral'), nil)
end

function TestJobOrder:test_falls_back_to_neutral_then_disliked()
    self.jobs:postNode(self.bush)
    -- nothing to mine: the neutral job, foraging
    local w = self.make({ main = ROLE_MINER, neutral = ROLE_FORAGER, disliked = ROLE_LUMBERJACK })
    lu.assertEquals(firstJob(w, { w }, self.world, self.jobs), ROLE_FORAGER)
    lu.assertNotNil(w:describeState():find('neutral job'))
    -- nothing to mine or forage, a tree to shake: the disliked job, last
    self:setUp()
    self.bush.ready = false; self.bush.timer = 999
    self.jobs:postNode(self.tree)
    w = self.make({ main = ROLE_MINER, neutral = ROLE_FORAGER, disliked = ROLE_LUMBERJACK })
    lu.assertEquals(firstJob(w, { w }, self.world, self.jobs), ROLE_LUMBERJACK)
    lu.assertNotNil(w:describeState():find('disliked job'))
end

function TestJobOrder:test_never_takes_a_job_outside_its_three()
    -- a builder's work and a tree to shake; this morphi does neither
    self.bush.ready = false; self.bush.timer = 999
    self.jobs:postNode(self.tree)
    local site = assert(self.world:addSite(SITE_BIN, 8, 5))
    self.jobs:postSite(site)
    local w = self.make({ main = ROLE_MINER, neutral = ROLE_FORAGER, disliked = ROLE_BUILDER })
    -- it builds (disliked), but never gathers
    for _ = 1, 100 do
        run({ w }, self.world, self.jobs, 0.1)
        lu.assertNotEquals(w.doing, ROLE_LUMBERJACK)
    end
    lu.assertTrue(self.tree.ready, 'nobody gathered sticks from the tree')
end

function TestJobOrder:test_only_a_builder_builds_in_free_play()
    self.bush.ready = false; self.bush.timer = 999
    local site = assert(self.world:addSite(SITE_BIN, 8, 5))
    self.jobs:postSite(site)
    local w = self.make({ main = ROLE_FORAGER, neutral = ROLE_LUMBERJACK, disliked = ROLE_MINER })
    run({ w }, self.world, self.jobs, 6)
    lu.assertTrue(self.jobs:hasJobForSite(site), 'no builder among its jobs: the bin waits')
    lu.assertNil(w.doing)
    -- set builder as its neutral job and it goes and builds
    lu.assertTrue((w:setJob('neutral', ROLE_BUILDER)))
    lu.assertEquals(firstJob(w, { w }, self.world, self.jobs), ROLE_BUILDER)
end

function TestJobOrder:test_action_time_follows_the_job_being_done()
    self.jobs:postNode(self.bush)
    -- a miner foraging picks at a forager's pace, not a miner's
    local w = self.make({ main = ROLE_MINER, neutral = ROLE_FORAGER, disliked = ROLE_LUMBERJACK }, 3)
    lu.assertEquals(w:doingInfo().actionSeconds, ROLES[ROLE_MINER].actionSeconds)
    firstJob(w, { w }, self.world, self.jobs)
    lu.assertEquals(w:doingInfo().actionSeconds, ROLES[ROLE_FORAGER].actionSeconds)
end

function TestJobOrder:test_idle_says_why_naming_the_job()
    self.bush.ready = false; self.bush.timer = 999
    self.tree.ready = false; self.tree.timer = 999
    local w = self.make({ main = ROLE_BUILDER, disliked = ROLE_MINER })
    local reasons = w:idleReasons()
    lu.assertEquals(reasons[1].job, ROLE_BUILDER)
    lu.assertEquals(reasons[1].why, 'none')
    lu.assertEquals(#reasons, 2, 'no neutral job: main and disliked only')
    local text = Worker.idleText(reasons, true, nil)
    lu.assertNotNil(text:find('builder'))
    lu.assertNotNil(text:find('no neutral job set'))
end

TestJobsArcade = {}

function TestJobsArcade:test_arcade_keeps_one_fixed_job_each()
    H.newLevel(1, 'arcade', 1)
    for _, w in ipairs(H.game().workers) do
        lu.assertNil(w.jobSet)
        lu.assertEquals(w.role, ARCADE_ROLE[w.sheet])
        lu.assertFalse((w:setJob('main', ROLE_MINER)))
    end
end

TestJobsExport = {}

function TestJobsExport:test_the_run_export_carries_the_jobs()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    for _ = 1, math.floor(DAY_SECONDS * 2 / 0.1) do love.update(0.1) end
    local json = g.stats:export('jobs')
    lu.assertNotNil(json:find('"format":' .. STATS_FORMAT, 1, true))
    lu.assertEquals(STATS_FORMAT, 2)
    local w = g.workers[1]
    lu.assertNotNil(json:find('"main":"' .. w.jobSet.main .. '"', 1, true))
    lu.assertNotNil(json:find('"disliked":"' .. w.jobSet.disliked .. '"', 1, true))
    lu.assertNotNil(json:find('"idleByMain"', 1, true))
end

TestFollowNav = {}

function TestFollowNav:test_next_morphi_is_there_without_following()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    g.follow = false
    g.selectedWorker = nil
    love.draw()
    local ui = H.ui()
    lu.assertEquals(#ui.followNav, 2, 'the < and > buttons show with nobody followed')
    local r = ui.followNav[2]
    love.mousepressed((r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale, 1, false)
    lu.assertTrue(g.selectedWorker == g.workers[1])
    lu.assertFalse(g.follow, 'picking the next morphi does not start following')
    love.mousepressed((r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale, 1, false)
    lu.assertTrue(g.selectedWorker == g.workers[2])
end

TestAlerts = {}

function TestAlerts:test_only_bad_news_pops_up_one_at_a_time_with_a_log_button()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local ui = H.ui()
    ui.alerts = {}
    H.announce('Dave has nothing to do', { x = 3, y = 3 }, 'hardship')
    H.announce('Summer 1 begins.')
    lu.assertEquals(#ui.alerts, 0, 'hardships and news go to the log only')
    H.announce('Priya is fed up and close to leaving the band.', { x = 2, y = 2 }, 'warning')
    H.announce('Kenji starved and wandered off into the wilds.', { x = 4, y = 4 }, 'left')
    lu.assertEquals(#ui.alerts, 1, 'alerts do not stack')
    lu.assertNotNil(ui.alerts[1].text:find('Kenji'))
    love.draw()
    local r = ui.alertLog
    lu.assertNotNil(r, 'the alert has a LOG button')
    love.mousepressed((r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale, 1, false)
    lu.assertEquals(H.state(), 'log')
    H.setState('playing')
    ui.alerts = {}
end

TestStripAndUnits = {}

function TestStripAndUnits:test_follow_on_the_strip_and_jobs_on_the_units_list()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g, ui = H.game(), H.ui()
    -- by finger, laid out for touch as after a first touch
    ui.touch = true
    love.resize(1280, 720)
    Stub.fingers = {}
    love.update(0)
    local function tap(r)
        Stub.fingers = { 't' }
        love.touchpressed('t', (r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale)
        love.touchreleased('t')
        Stub.fingers = {}
    end
    g.follow = false
    g.selectedWorker = g.workers[1]
    love.draw()
    local f = ui.followButton
    lu.assertNotNil(f, 'FOLLOW is on the strip')
    tap(f)
    lu.assertTrue(g.follow)
    -- the units list: JOBS on a row opens that morphi's job screen
    H.setState('units')
    love.draw()
    local jb
    for _, b in ipairs(ui.unitButtons) do
        if b.what == 'jobs' and b.worker == g.workers[3] then jb = b end
    end
    lu.assertNotNil(jb, 'a JOBS button on each free play row')
    tap(jb)
    lu.assertEquals(H.state(), 'jobs')
    lu.assertTrue(g.selectedWorker == g.workers[3])
    H.setState('playing')
    ui.touch = false
    love.resize(1280, 720)
end

TestJobsScreen = {}

function TestJobsScreen:test_the_job_screen_sets_main_and_neutral_and_refuses_the_dislike()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local w = g.workers[1]
    g.selectedWorker = w
    H.openJobs()
    lu.assertEquals(H.state(), 'jobs')
    love.draw()
    local js = w.jobSet
    local other
    for _, job in ipairs(JobSets.JOBS) do
        if job ~= js.main and job ~= js.disliked and job ~= js.neutral then other = job end
    end
    H.pressJob('job:neutral:' .. other)
    lu.assertEquals(js.neutral, other)
    H.pressJob('job:neutral:none')
    lu.assertNil(js.neutral)
    local dislike = js.disliked
    H.pressJob('job:neutral:' .. dislike)
    lu.assertNil(js.neutral, 'the disliked job is never the fallback')
    H.pressJob('job:main:' .. dislike)
    lu.assertEquals(js.main, dislike, 'the disliked job can be the main job')
    lu.assertEquals(js.disliked, dislike)
    H.pressJob('job:main:' .. other)
    lu.assertEquals(js.main, other)
    lu.assertEquals(w.role, other)
    -- the next morphi, without leaving the job screen (by finger: lay the
    -- screen out for touch first, as the first touch would)
    H.ui().touch = true
    love.resize(1280, 720)
    love.draw()
    local ui = H.ui()
    local nb
    for _, pb in ipairs(ui.panelButtons) do if pb.id == 'jobnext' then nb = pb end end
    lu.assertNotNil(nb)
    Stub.fingers = {}
    love.update(0) -- forget fingers an earlier test left down
    Stub.fingers = { 'n' }
    love.touchpressed('n', (nb.x + nb.w / 2) * ui.scale, (nb.y + nb.h / 2) * ui.scale)
    love.touchreleased('n')
    Stub.fingers = {}
    lu.assertTrue(g.selectedWorker == g.workers[2], 'the > button picks the next morphi')
    lu.assertEquals(H.state(), 'jobs')
    love.keypressed('[')
    lu.assertTrue(g.selectedWorker == g.workers[1])
    -- UNITS goes back to the units list
    love.draw()
    local ub
    for _, pb in ipairs(ui.panelButtons) do if pb.id == 'units' then ub = pb end end
    lu.assertNotNil(ub)
    Stub.fingers = { 'u' }
    love.touchpressed('u', (ub.x + ub.w / 2) * ui.scale, (ub.y + ub.h / 2) * ui.scale)
    love.touchreleased('u')
    Stub.fingers = {}
    lu.assertEquals(H.state(), 'units')
    H.openJobs()
    love.keypressed('escape')
    lu.assertEquals(H.state(), 'playing')
    H.ui().touch = false
    love.resize(1280, 720)
end

function TestJobsScreen:test_a_tap_on_jobs_and_a_job_button_works_on_a_phone()
    Stub.width, Stub.height = 393, 852
    H.ui().touch = true
    love.resize(393, 852)
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local g = H.game()
    local w = g.workers[2]
    g.selectedWorker = w
    love.draw()
    local ui = H.ui()
    local b = ui.jobsButton
    lu.assertNotNil(b, 'the strip shows JOBS for a free play morphi')
    local s = ui.scale
    love.touchpressed('a', (b.x + b.w / 2) * s, (b.y + b.h / 2) * s)
    love.touchreleased('a')
    lu.assertEquals(H.state(), 'jobs')
    love.draw()
    local target
    for _, pb in ipairs(ui.panelButtons) do
        if pb.id == 'job:neutral:none' then target = pb end
    end
    lu.assertNotNil(target)
    love.touchpressed('b', (target.x + target.w / 2) * s, (target.y + target.h / 2) * s)
    love.touchreleased('b')
    lu.assertNil(w.jobSet.neutral)
    lu.assertEquals(H.state(), 'jobs')
    Stub.width, Stub.height = 1280, 720
    H.ui().touch = false
    love.resize(1280, 720)
    H.setState('playing')
end

os.exit(lu.LuaUnit.run())
