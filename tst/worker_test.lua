local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')

local function run(workers, world, jobs, seconds, dt)
    dt = dt or 0.05
    local clock = 0
    local steps = math.floor(seconds / dt)
    for _ = 1, steps do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, function(n) jobs:postNode(n) end)
        for _, w in ipairs(workers) do w:update(dt, clock) end
    end
    return clock
end

-- b: ripe bush (reachable) at (2,2)   T: tree at (9,2)   G: ore at (3,6) in a stone wall
-- pocket bush at (5,8) walled in
local GRID = {
    '..........',
    '.b......T.',
    '..........',
    '....BB....',
    '....BB....',
    '..G.......',
    '..#####...',
    '..#.b.#...',
    '..#####...',
}

TestWorker = {}
function TestWorker:setUp()
    self.world = World.fromGrid(GRID, Rng.new(1))
    self.jobs = Jobs.new()
    self.scoring = Scoring.new(2)
    self.complaints = {}
    self.events = {}
    self.bush = self.world:get(2, 2).node
    self.tree = self.world:get(9, 2).node
    self.ore = self.world:get(3, 6).node
    self.pocket = self.world:get(5, 8).node
    self.pocket.ready = false; self.pocket.timer = 999
    self.opts = function(role, x, y)
        return {
            x = x or 5, y = y or 4, role = role, name = 'Dave', drain = 0.5,
            onComplain = function(_, reason, node) self.complaints[#self.complaints + 1] = { reason = reason, node = node } end,
            onEvent = function(_, name, data) self.events[#self.events + 1] = name .. (data and (':' .. tostring(data)) or '') end,
        }
    end
end

function TestWorker:testForagerPicksAndStocksThePantry()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    self.jobs:postNode(self.bush)
    run({ w }, self.world, self.jobs, 12)
    lu.assertEquals(self.scoring.output, 1)
    lu.assertEquals(self.scoring.delivered.food, 1)
    lu.assertEquals(self.world.breakroom.food, 1)
    lu.assertFalse(self.bush.ready)
    lu.assertNil(w.carrying)
    lu.assertEquals(self.events[1], 'work:bush')
    lu.assertEquals(self.events[2], 'deliver:food')
    lu.assertEquals(#self.complaints, 0)
end

function TestWorker:testLumberjackChopsTreeIntoStump()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK))
    self.jobs:postNode(self.bush)   -- not my job
    self.jobs:postNode(self.tree)
    run({ w }, self.world, self.jobs, 14)
    lu.assertEquals(self.scoring.delivered.logs, 1)
    lu.assertEquals(self.scoring.delivered.food, 0)
    lu.assertFalse(self.tree.ready)
    lu.assertEquals(self.tree.timer > 0, true)
    lu.assertTrue(self.jobs:hasJobFor(self.bush)) -- still queued for a forager
    lu.assertEquals(self.events[2], 'deliver:logs')
end

function TestWorker:testMinerWorksOreFromNextDoorAndOpensTheTile()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    self.jobs:postNode(self.ore)
    run({ w }, self.world, self.jobs, 14)
    lu.assertEquals(self.scoring.delivered.gold, 1)
    lu.assertEquals(self.world:get(3, 6).type, TILE_DIRT)
    lu.assertNil(self.world:get(3, 6).node)
    lu.assertEquals(#self.world:nodesOfKind(NODE_ORE), 0)
end

function TestWorker:testHungryMorphiEatsFromThePantryFirst()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    self.world.breakroom.food = 2
    w.hunger = 20
    run({ w }, self.world, self.jobs, 4)
    lu.assertEquals(self.world.breakroom.food, 1)
    lu.assertTrue(w.hunger > 50, 'hunger was ' .. w.hunger)
    lu.assertTrue(self.bush.ready) -- left the bush alone
    lu.assertEquals(self.events[1], 'eat')
end

function TestWorker:testHungryMorphiEatsFromABushWhenPantryIsEmpty()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK))
    w.hunger = 20
    run({ w }, self.world, self.jobs, 8)
    lu.assertTrue(w.hunger > 40, 'hunger was ' .. w.hunger)
    lu.assertFalse(self.bush.ready)
    lu.assertEquals(self.scoring.output, 0)
    lu.assertEquals(self.events[1], 'eat')
end

function TestWorker:testComplainsAboutWalledOffBush()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    self.bush.ready = false; self.bush.timer = 999
    self.pocket.ready = true
    self.jobs:postNode(self.pocket)
    run({ w }, self.world, self.jobs, 2)
    lu.assertEquals(#self.complaints, 1)
    lu.assertEquals(self.complaints[1].reason, 'blocked')
    lu.assertEquals(self.complaints[1].node, self.pocket)
    lu.assertEquals(self.scoring.complaints, 1)
    lu.assertEquals(self.jobs:count(), 1)       -- job went back on the queue
    lu.assertTrue(w:isIcked(5, 8))
    lu.assertEquals(w.state, 'sulking')
    run({ w }, self.world, self.jobs, 6)
    lu.assertEquals(#self.complaints, 1)
    lu.assertEquals(self.scoring.output, 0)
    -- dig it open and the forager gets to it
    self.world:dig(4, 7)
    w.icks = {}
    run({ w }, self.world, self.jobs, 15)
    lu.assertEquals(self.scoring.delivered.food, 1)
end

function TestWorker:testHungryAndBlockedComplains()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    self.bush.ready = false; self.bush.timer = 999
    self.pocket.ready = true
    w.hunger = 10
    run({ w }, self.world, self.jobs, 1.5)
    lu.assertEquals(self.complaints[1].reason, 'hungry')
end

function TestWorker:testStarvesAndQuits()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK))
    self.bush.ready = false; self.bush.timer = 999
    w.hunger = 3
    w.drain = 2
    run({ w }, self.world, self.jobs, 2)
    lu.assertEquals(w.state, 'quitting')
    lu.assertEquals(self.scoring.quits, 1)
    lu.assertFalse(w:isWorking())
    lu.assertEquals(self.events[#self.events], 'quit')
    run({ w }, self.world, self.jobs, 6)
    lu.assertFalse(w.alive)
end

function TestWorker:testThreeRolesShareOneQueue()
    local f = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER, 5, 4))
    local l = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_LUMBERJACK, 6, 4))
    local m = Worker.new(self.world, self.jobs, self.scoring, Rng.new(4), self.opts(ROLE_MINER, 5, 5))
    self.jobs:postNode(self.ore)
    self.jobs:postNode(self.bush)
    self.jobs:postNode(self.tree)
    run({ f, l, m }, self.world, self.jobs, 16)
    lu.assertEquals(self.scoring.delivered.food, 1)
    lu.assertEquals(self.scoring.delivered.logs, 1)
    lu.assertEquals(self.scoring.delivered.gold, 1)
    lu.assertEquals(self.jobs:count(), 0)
end

TestSimulation = {}
local function simulateQuarter(difficultyIndex)
    local seed = Rng.seedToNumber(DEFAULT_SEED)
    local rng = Rng.new(seed)
    local world = World.generate(seed, rng)
    world:spawnAllNodes(NODES_INITIAL)
    local jobs = Jobs.new()
    for _, node in ipairs(world.nodes) do
        if node.ready then jobs:postNode(node) end
    end
    local scoring = Scoring.new(difficultyIndex)
    local workers = {}
    local spots = world:spawnTiles(3)
    local reasons = {}
    for i = 1, DIFFICULTIES[difficultyIndex].workers do
        local s = spots[(i - 1) % #spots + 1]
        local role = HIRE_ORDER[(i - 1) % #HIRE_ORDER + 1]
        workers[#workers + 1] = Worker.new(world, jobs, scoring, rng, {
            x = s.x, y = s.y, name = 'W' .. i, role = role, drain = scoring.drain,
            onComplain = function(_, reason) reasons[reason] = (reasons[reason] or 0) + 1 end,
        })
    end
    local clock = 0
    local dt = 1 / 30
    local ended = false
    local start = os.clock()
    while clock < QUARTER_SECONDS + 1 and not ended do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, function(n) jobs:postNode(n) end)
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
    local rs = ''
    for k, v in pairs(reasons) do rs = rs .. k .. '=' .. v .. ' ' end
    print(string.format('  %-14s Q1 unaided seed %s: food %d logs %d gold %d, complaints %d (%s), quits %d, fed %d%%, pantry %d, grade %s (%.2fs)',
        DIFFICULTIES[difficultyIndex].name, DEFAULT_SEED, report.food, report.logs, report.gold, report.complaints, rs,
        report.attrition, report.fedPct, world.breakroom.food, report.grade, elapsed))
    return report
end
function TestSimulation:testFullQuarterOnGeneratedWorld()
    for d = 1, #DIFFICULTIES do
        local report = simulateQuarter(d)
        if d == 2 then
            lu.assertTrue(report.output >= 6, 'morphis delivered only ' .. report.output)
            lu.assertTrue(report.logs >= 1 and report.gold >= 1 and report.food >= 1, 'every role should deliver')
            lu.assertTrue(report.complaints <= 14, 'complaint spam: ' .. report.complaints)
            lu.assertTrue(report.attrition == 0, 'quits with nobody helping: ' .. report.attrition)
        end
    end
end

os.exit(lu.LuaUnit.run())
