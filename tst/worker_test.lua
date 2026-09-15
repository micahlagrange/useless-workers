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
    '...SBBS...',
    '...SBBS...',
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
    lu.assertEquals(self.world:storedCount(ITEM_FOOD), 1)
    local item = self.world.items[1]
    lu.assertEquals(item.kind, ITEM_FOOD)
    -- stored on a built storage tile
    lu.assertTrue(self.world:get(item.x, item.y).storage)
    lu.assertFalse(self.bush.ready)
    lu.assertNil(w:carrying())
    lu.assertEquals(self.events[1], 'work:bush')
    lu.assertEquals(self.events[2], 'deliver:food')
    lu.assertEquals(#self.complaints, 0)
    -- the forager stepped off the food it just dropped
    local t = w:tile()
    lu.assertNil(self.world:get(t.x, t.y).item)
end

function TestWorker:testOneFoodPerTileClosestFirst()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    local extra = self.world:addNode(NODE_BUSH, 8, 1); extra.ready = true
    local extra2 = self.world:addNode(NODE_BUSH, 1, 5); extra2.ready = true
    self.jobs:postNode(self.bush)
    self.jobs:postNode(extra)
    self.jobs:postNode(extra2)
    run({ w }, self.world, self.jobs, 45)
    local count = self.world:storedCount(ITEM_FOOD)
    lu.assertTrue(count >= 3, 'stored only ' .. count) -- bushes ripen again, so possibly more
    lu.assertTrue(count <= self.world:storageCapacity())
    local seen = {}
    local ring = self.world:storageTiles()
    for _, item in ipairs(self.world.items) do
        local key = item.x .. ':' .. item.y
        lu.assertNil(seen[key], 'two items on one tile')
        seen[key] = true
        -- items fill the closest storage tiles first, so every item's rank is within the count
        local rank
        for i, st in ipairs(ring) do if st.x == item.x and st.y == item.y then rank = i end end
        lu.assertTrue(rank ~= nil and rank <= count, 'item at rank ' .. tostring(rank) .. ' of ' .. count)
    end
end

function TestWorker:testForagerWaitsWhenThereIsNoStorage()
    local world = World.fromGrid({
        '..........',
        '.b........',
        '..........',
        '....BB....',
        '....BB....',
        '..........',
    }, Rng.new(1))
    local w = Worker.new(world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    self.jobs:postNode(world:get(2, 2).node)
    run({ w }, world, self.jobs, 10)
    lu.assertEquals(self.scoring.output, 0)
    lu.assertTrue(world:get(2, 2).node.ready)        -- left it on the bush
    lu.assertEquals(self.jobs:count('forage'), 1)     -- job still waiting
    -- a storage site goes up: the idle forager builds it, then forages
    world.stock.logs = 2
    local site = world:addSite(SITE_STORAGE, 3, 4)
    self.jobs:postSite(site)
    run({ w }, world, self.jobs, 8)
    lu.assertTrue(world:get(3, 4).storage, 'storage not built')
    lu.assertEquals(self.events[1], 'built:storage')
    run({ w }, world, self.jobs, 14)
    lu.assertEquals(self.scoring.delivered.food, 1)
    lu.assertNotNil(world:get(3, 4).item)
end

function TestWorker:testMinerWorksAWholeAreaWithoutIdling()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    -- the whole bottom wall of the pocket, one drag: only the ends touch open ground at first
    local area = self.world:newArea()
    for x = 3, 7 do self.world:addSite(SITE_MINE, x, 9, area) end
    self.world:addSite(SITE_MINE, 4, 7, area)   -- a wall tile of the pocket itself
    lu.assertEquals(#area.sites, 6)
    self.jobs:postArea(area)
    local idleBetween, mined, sawWorking = 0, 0, false
    for _ = 1, 1200 do
        run({ w }, self.world, self.jobs, 0.05)
        if w.state == 'working' then sawWorking = true end
        if sawWorking and #area.sites > 0 and #area.sites < 6 and w.state == 'idle' then idleBetween = idleBetween + 1 end
        if #area.sites == 0 then break end
    end
    lu.assertEquals(#area.sites, 0, 'area not finished')
    lu.assertEquals(idleBetween, 0, 'went idle between tiles')
    for x = 3, 7 do lu.assertEquals(self.world:get(x, 9).type, TILE_DIRT) end
    lu.assertEquals(self.world:get(4, 7).type, TILE_DIRT)
    lu.assertEquals(#self.world.areas, 0)
    lu.assertNil(w.targetArea)
    lu.assertNil(self.jobs:take('mine'))
    lu.assertTrue(self.world:isReachable(5, 8))  -- the pocket is open now
    lu.assertEquals(#self.complaints, 0)
end

function TestWorker:testMinerHaulsGoldThenReturnsToTheArea()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    local area = self.world:newArea()
    self.world:addSite(SITE_MINE, 3, 6, area)   -- the ore tile
    self.world:addSite(SITE_MINE, 3, 7, area)   -- plain stone behind it
    self.world:addSite(SITE_MINE, 4, 7, area)
    self.jobs:postArea(area)
    run({ w }, self.world, self.jobs, 30)
    lu.assertEquals(self.scoring.delivered.gold, 1)
    lu.assertEquals(self.world.stock.gold, 1)
    lu.assertEquals(#area.sites, 0)
    lu.assertEquals(self.world:get(4, 7).type, TILE_DIRT)
end

function TestWorker:testHungryMinerEatsBetweenTilesThenComesBack()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    self.world:storeItem(ITEM_FOOD, 7, 4, 3)
    local area = self.world:newArea()
    self.world:addSite(SITE_MINE, 4, 7, area)
    self.world:addSite(SITE_MINE, 5, 7, area)
    self.world:addSite(SITE_MINE, 6, 7, area)
    self.jobs:postArea(area)
    run({ w }, self.world, self.jobs, 3)
    lu.assertEquals(w.targetArea, area)
    w.hunger = HUNGER_EAT_THRESHOLD - 1
    run({ w }, self.world, self.jobs, 40)
    lu.assertEquals(#area.sites, 0)
    lu.assertTrue(w.hunger > 40, 'did not eat, hunger ' .. w.hunger)
    -- the meal happened between the first and the last tile, never mid-tile
    local firstMined, lastMined, eat
    for i, e in ipairs(self.events) do
        if e == 'mined:mine' then firstMined = firstMined or i; lastMined = i end
        if e == 'eat' then eat = eat or i end
    end
    lu.assertNotNil(eat)
    lu.assertTrue(firstMined < eat and eat < lastMined, table.concat(self.events, ','))
end

function TestWorker:testMinerStopsAfterItsTileLimitAndComesBack()
    local opts = self.opts(ROLE_MINER)
    opts.mineLimit = 2
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), opts)
    local area = self.world:newArea()
    for x = 3, 7 do self.world:addSite(SITE_MINE, x, 9, area) end
    self.jobs:postArea(area)
    local released = false
    for _ = 1, 600 do
        run({ w }, self.world, self.jobs, 0.05)
        if #area.sites == 3 and w.targetArea == nil then released = true end
        if #area.sites == 0 then break end
    end
    lu.assertTrue(released, 'never let go of the area after two tiles')
    lu.assertEquals(#area.sites, 0)   -- but came back and finished it
    lu.assertEquals(w.areaTilesDone <= 2, true)
end

function TestWorker:testLogsAndGoldGoToTheStockpile()
    local l = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 6, 5))
    local m = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_MINER, 5, 5))
    self.jobs:postNode(self.tree)
    self.jobs:postNode(self.ore)
    run({ l, m }, self.world, self.jobs, 16)
    lu.assertEquals(self.world.stock.logs, 1)
    lu.assertEquals(self.world.stock.gold, 1)
    lu.assertEquals(self.scoring.delivered.logs, 1)
    lu.assertEquals(self.scoring.delivered.gold, 1)
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
    lu.assertEquals(self.world.stock.gold, 1)
end

function TestWorker:testHungryMorphiFetchesFromStorageIntoSlot2()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER))
    self.world:storeItem(ITEM_FOOD, 7, 4, 3)
    self.world:storeItem(ITEM_FOOD, 7, 5, 4)
    w.hunger = 20
    run({ w }, self.world, self.jobs, 5)
    lu.assertEquals(self.world:storedCount(ITEM_FOOD), 1)
    lu.assertTrue(w.hunger > 50, 'hunger was ' .. w.hunger)
    lu.assertTrue(self.bush.ready) -- left the bush alone
    lu.assertEquals(self.events[1], 'pickup:food')
    lu.assertEquals(self.events[2], 'eat')
    lu.assertNil(w.slots[SLOT_PERSONAL])
end

function TestWorker:testHungryWithSnackFinishesTheJobFirst()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK))
    w.slots[SLOT_PERSONAL] = { kind = ITEM_FOOD, fruit = 1 }
    self.jobs:postNode(self.tree)
    run({ w }, self.world, self.jobs, 0.6)
    lu.assertEquals(w.state, 'walking')
    lu.assertEquals(w.goal, 'work')
    w.hunger = HUNGER_EAT_THRESHOLD - 1
    run({ w }, self.world, self.jobs, 0.3)
    lu.assertEquals(w.state, 'walking') -- no interruption
    lu.assertNotNil(w.slots[SLOT_PERSONAL])
    run({ w }, self.world, self.jobs, 16)
    lu.assertEquals(self.scoring.delivered.logs, 1)
    -- once idle, the snack was the next thing it did
    lu.assertNil(w.slots[SLOT_PERSONAL])
    lu.assertTrue(w.hunger > 50, 'hunger was ' .. w.hunger)
    lu.assertEquals(self.events[#self.events], 'eat')
end

function TestWorker:testTakesABreakAfterEnoughWork()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 6, 5))
    w.workTime = BREAK_AFTER_SECONDS
    self.world:storeItem(ITEM_FOOD, 7, 5, 2)
    self.jobs:postNode(self.tree)
    run({ w }, self.world, self.jobs, 6)
    -- grabbed a snack from storage first, then rested in the break room
    lu.assertEquals(self.events[1], 'pickup:food')
    lu.assertEquals(w.slots[SLOT_PERSONAL].kind, ITEM_FOOD)
    local sawBreak = false
    for _ = 1, 200 do
        run({ w }, self.world, self.jobs, 0.1)
        if w.state == 'breaking' then
            sawBreak = true
            local t = w:tile()
            lu.assertEquals(self.world:get(t.x, t.y).type, TILE_BREAKROOM)
            break
        end
    end
    lu.assertTrue(sawBreak, 'never took the break')
    run({ w }, self.world, self.jobs, BREAK_SECONDS + 15)
    lu.assertEquals(w.breaksTaken, 1)
    lu.assertEquals(w.workTime < BREAK_AFTER_SECONDS, true)
    lu.assertTrue(self.jobs:hasJobFor(self.tree) or self.scoring.delivered.logs == 1 or w.targetNode == self.tree)
end

function TestWorker:testHungryMorphiEatsFromABushWhenStorageIsEmpty()
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
    world.stock = { logs = STARTING_STOCK.logs, gold = STARTING_STOCK.gold }
    world:spawnAllNodes(NODES_INITIAL)
    local jobs = Jobs.new()
    for _, node in ipairs(world.nodes) do
        if node.ready then jobs:postNode(node) end
    end
    -- what a player does first: two storage sites next to the break room
    local placed = 0
    for _, s in ipairs(world:spawnTiles(2)) do
        if placed < 2 and world:get(s.x, s.y).type ~= TILE_BREAKROOM and world:spend(COSTS.storage) then
            local site = world:addSite(SITE_STORAGE, s.x, s.y)
            if site then jobs:postSite(site); placed = placed + 1 end
        end
    end
    lu.assertEquals(placed, 2)
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
    lu.assertEquals(world:storageCapacity(), 2, 'storage sites were not built')
    local rs = ''
    for k, v in pairs(reasons) do rs = rs .. k .. '=' .. v .. ' ' end
    print(string.format('  %-14s Q1 unaided seed %s: food %d logs %d gold %d, complaints %d (%s), quits %d, fed %d%%, stored %d, grade %s (%.2fs)',
        DIFFICULTIES[difficultyIndex].name, DEFAULT_SEED, report.food, report.logs, report.gold, report.complaints, rs,
        report.attrition, report.fedPct, world:storedCount(ITEM_FOOD), report.grade, elapsed))
    print(string.format('    stockpile: logs %d gold %d', world.stock.logs, world.stock.gold))
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
