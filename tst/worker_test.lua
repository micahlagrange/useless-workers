local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')

local function run(workers, world, jobs, seconds, dt, onRipe)
    dt = dt or 0.05
    local clock = 0
    local steps = math.floor(seconds / dt)
    for _ = 1, steps do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, onRipe or function(t) jobs:postHarvest(t) end)
        for _, w in ipairs(workers) do w:update(dt, clock) end
    end
    return clock
end

TestWorker = {}
function TestWorker:setUp()
    self.world = World.fromGrid({
        '..........',
        '.T........',
        '..........',
        '....BB....',
        '....BB....',
        '..........',
        '..#####...',
        '..#.T.#...',
        '..#####...',
    }, Rng.new(1))
    self.jobs = Jobs.new()
    self.scoring = Scoring.new(2)
    self.complaints = {}
    self.events = {}
    self.worker = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), {
        x = 5, y = 4, name = 'Dave', drain = 0.5,
        onComplain = function(_, reason, x, y) self.complaints[#self.complaints + 1] = { reason = reason, x = x, y = y } end,
        onEvent = function(_, name) self.events[#self.events + 1] = name end,
    })
end

function TestWorker:testHarvestsAndDelivers()
    local tree = self.world.trees[1]           -- (2,2), reachable, ripe
    local pocket = self.world.trees[2]         -- (5,8), walled in
    pocket.ripe = false; pocket.timer = 999
    self.jobs:postHarvest(tree)
    run({ self.worker }, self.world, self.jobs, 12)
    lu.assertEquals(self.scoring.output, 1)
    lu.assertEquals(self.worker.delivered, 1)
    lu.assertFalse(tree.ripe)
    lu.assertNil(self.worker.carrying)
    lu.assertEquals(self.jobs:count(), 0)
    lu.assertEquals(self.events[1], 'harvest')
    lu.assertEquals(self.events[2], 'deliver')
    lu.assertEquals(#self.complaints, 0)
end

function TestWorker:testEatsWhenHungry()
    self.world.trees[2].ripe = false; self.world.trees[2].timer = 999
    self.worker.hunger = 20
    run({ self.worker }, self.world, self.jobs, 8)
    lu.assertTrue(self.worker.hunger > 40, 'hunger was ' .. self.worker.hunger)
    lu.assertEquals(self.scoring.output, 0)
    lu.assertEquals(self.events[1], 'eat')
end

function TestWorker:testComplainsAboutWalledOffFruit()
    self.world.trees[1].ripe = false; self.world.trees[1].timer = 999
    local pocket = self.world.trees[2]
    self.jobs:postHarvest(pocket)
    run({ self.worker }, self.world, self.jobs, 2)
    lu.assertEquals(#self.complaints, 1)
    lu.assertEquals(self.complaints[1].reason, 'blocked')
    lu.assertEquals(self.complaints[1].x, 5)
    lu.assertEquals(self.scoring.complaints, 1)
    lu.assertEquals(self.jobs:count(), 1)       -- job went back on the queue
    lu.assertTrue(self.worker:isIcked(5, 8))
    lu.assertEquals(self.worker.state, 'sulking')
    -- after the sulk the worker leaves the icked tree alone and wanders instead
    run({ self.worker }, self.world, self.jobs, 6)
    lu.assertEquals(#self.complaints, 1)
    lu.assertEquals(self.scoring.output, 0)
    -- dig it open and the worker gets to it
    self.world:dig(4, 7)
    self.worker.icks = {}
    run({ self.worker }, self.world, self.jobs, 15)
    lu.assertEquals(self.scoring.output, 1)
end

function TestWorker:testHungryAndBlockedComplains()
    self.world.trees[1].ripe = false; self.world.trees[1].timer = 999
    self.worker.hunger = 10
    run({ self.worker }, self.world, self.jobs, 1.5)
    lu.assertEquals(self.complaints[1].reason, 'hungry')
end

function TestWorker:testStarvesAndQuits()
    self.world.trees[1].ripe = false; self.world.trees[1].timer = 999
    self.world.trees[2].ripe = false; self.world.trees[2].timer = 999
    self.worker.hunger = 3
    self.worker.drain = 2
    run({ self.worker }, self.world, self.jobs, 2)
    lu.assertEquals(self.worker.state, 'quitting')
    lu.assertEquals(self.scoring.quits, 1)
    lu.assertFalse(self.worker:isWorking())
    lu.assertEquals(self.events[#self.events], 'quit')
    run({ self.worker }, self.world, self.jobs, 6)
    lu.assertFalse(self.worker.alive)
end

function TestWorker:testTwoWorkersShareQueue()
    local other = Worker.new(self.world, self.jobs, self.scoring, Rng.new(9), { x = 6, y = 5, name = 'Priya', drain = 0.5 })
    self.world.trees[2].ripe = false; self.world.trees[2].timer = 999
    local extra = self.world:addTree(9, 2); extra.ripe = true
    self.jobs:postHarvest(self.world.trees[1])
    self.jobs:postHarvest(extra)
    run({ self.worker, other }, self.world, self.jobs, 12)
    lu.assertEquals(self.scoring.output, 2)
    lu.assertEquals(self.worker.delivered + other.delivered, 2)
end

TestSimulation = {}
local function simulateQuarter(difficultyIndex)
    local seed = Rng.seedToNumber(DEFAULT_SEED)
    local rng = Rng.new(seed)
    local world = World.generate(seed, rng)
    world:spawnTrees(TREES_INITIAL)
    local jobs = Jobs.new()
    local scoring = Scoring.new(difficultyIndex)
    local workers = {}
    local spots = world:spawnTiles(3)
    for i = 1, DIFFICULTIES[difficultyIndex].workers do
        local s = spots[(i - 1) % #spots + 1]
        workers[#workers + 1] = Worker.new(world, jobs, scoring, rng, { x = s.x, y = s.y, name = 'W' .. i, drain = scoring.drain })
    end
    local clock = 0
    local dt = 1 / 30
    local ended = false
    local start = os.clock()
    while clock < QUARTER_SECONDS + 1 and not ended do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, function(t) jobs:postHarvest(t) end)
        local count, sum = 0, 0
        for _, w in ipairs(workers) do
            w:update(dt, clock)
            if w:isWorking() then count = count + 1; sum = sum + w.hunger end
        end
        ended = scoring:update(dt, count > 0 and sum / count or nil)
    end
    local elapsed = os.clock() - start
    lu.assertTrue(ended)
    lu.assertTrue(elapsed < 20, 'quarter simulation took ' .. elapsed .. 's')
    local report = scoring:closeQuarter(#workers)
    print('  ' .. DIFFICULTIES[difficultyIndex].name .. ' Q1 unaided on seed ' .. DEFAULT_SEED .. ': output ' .. report.output ..
        ', complaints ' .. report.complaints .. ', quits ' .. report.attrition .. ', fed ' .. report.fedPct ..
        '%, grade ' .. report.grade .. ' (' .. string.format('%.2f', elapsed) .. 's)')
    return report
end
function TestSimulation:testFullQuarterOnGeneratedWorld()
    for d = 1, #DIFFICULTIES do
        local report = simulateQuarter(d)
        if d == 2 then
            lu.assertTrue(report.output >= 6, 'workers delivered only ' .. report.output)
            lu.assertTrue(report.complaints <= 12, 'complaint spam: ' .. report.complaints)
            lu.assertTrue(report.attrition == 0, 'quits with nobody helping: ' .. report.attrition)
        end
    end
end

os.exit(lu.LuaUnit.run())
