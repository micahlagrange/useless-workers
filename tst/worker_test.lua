local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')
local Stats = require('src.stats')

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
    -- everyone in these tests eats steak and every bush grows it
    for _, n in ipairs(self.world.nodes) do n.food = 'steak' end
    self.opts = function(role, x, y)
        return {
            x = x or 5, y = y or 4, role = role, name = 'Dave', drain = 0.5, diet = 'steak',
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
    lu.assertTrue(self.world:get(item.x, item.y).storage > 0)
    lu.assertFalse(self.bush.ready)
    lu.assertNil(w:carrying())
    lu.assertEquals(self.events[1], 'work:bush')
    lu.assertEquals(self.events[2], 'deliver:food')
    lu.assertEquals(#self.complaints, 0)
    -- the forager stepped off the food it just dropped
    local t = w:tile()
    lu.assertEquals(#self.world:get(t.x, t.y).items, 0)
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
    lu.assertTrue(world:get(3, 4).storage > 0, 'storage not built')
    lu.assertEquals(self.events[1], 'built:storage')
    run({ w }, world, self.jobs, 14)
    lu.assertEquals(self.scoring.delivered.food, 1)
    lu.assertEquals(#world:get(3, 4).items, 1)
end

-- Storage filled up while it was picking: the food stays in its hands
-- until there is somewhere to put it, it never vanishes.
function TestWorker:testPickedFoodWithNowhereToGoIsKept()
    local world = World.fromGrid({
        '..........',
        '.b........',
        '..........',
        '....BB....',
        '....BB....',
        '..........',
    }, Rng.new(1))
    local w = Worker.new(world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER, 2, 3))
    local bush = world:get(2, 2).node
    bush.claimedBy = w
    w.targetNode = bush
    w.state = 'working'
    w:finishAction()
    lu.assertNotNil(w:carrying(), 'the food went nowhere')
    lu.assertEquals(w:carrying().kind, CARGO_FOOD)
    lu.assertEquals(w.state, 'idle')
    run({ w }, world, self.jobs, 5)
    lu.assertNotNil(w:carrying())
    lu.assertStrContains(w:describeState(), 'no stash')
    -- a bin goes up: the food goes into it
    world.stock.logs = 2
    local site = world:addSite(SITE_STORAGE, 3, 4)
    world:completeSite(site)
    run({ w }, world, self.jobs, 10)
    lu.assertNil(w:carrying())
    lu.assertEquals(#world:get(3, 4).items, 1)
end

-- The tool is held on the facing side, so a morphi turns to its work,
-- whichever way its last step went.
function TestWorker:testFacesTheWorkWhenStarting()
    local world = World.fromGrid({
        '..........',
        '.b........',
        '..........',
    }, Rng.new(1))
    local w = Worker.new(world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER, 3, 2))
    w.facing = 'right'
    w.targetNode = world:get(2, 2).node
    w.goal = 'work'
    w:arrive()
    lu.assertEquals(w.state, 'working')
    lu.assertEquals(w.facing, 'left')
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
    self.world:storeItem(ITEM_FOOD, 7, 4, 'steak')
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

function TestWorker:testGathererShakesSticksAndTheTreeGrowsBack()
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
    -- the tree stays where it was, bare, and grows its twigs back
    local still = false
    for _, n in ipairs(self.world.nodes) do if n == self.tree then still = true end end
    lu.assertTrue(still, 'a shaken tree stays standing')
    self.world:update(TREE_REGROW_SECONDS + 1, function() end)
    lu.assertTrue(self.tree.ready, 'its twigs grew back')
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
    self.world:storeItem(ITEM_FOOD, 7, 4, 'steak')
    self.world:storeItem(ITEM_FOOD, 7, 5, 'steak')
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
    w.slots[SLOT_PERSONAL] = { kind = ITEM_FOOD, food = 'steak' }
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
    self.world:storeItem(ITEM_FOOD, 7, 5, 'steak')
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

function TestWorker:testTwoTiredMorphisRestOnDifferentTiles()
    local a = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 6, 5))
    local b = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_LUMBERJACK, 6, 5))
    b.name = 'Priya'
    a.workTime, b.workTime = BREAK_AFTER_SECONDS, BREAK_AFTER_SECONDS
    local sawBoth = false
    for _ = 1, 200 do
        run({ a, b }, self.world, self.jobs, 0.1)
        if a.state == 'breaking' and b.state == 'breaking' then
            sawBoth = true
            local ta, tb = a:tile(), b:tile()
            lu.assertFalse(ta.x == tb.x and ta.y == tb.y, 'both napping on the same tile')
            break
        end
    end
    lu.assertTrue(sawBoth, 'both should be on a break at once')
end

function TestWorker:testBedIsAShorterBetterBreak()
    self.world:markBed(7, 2)
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 6, 5))
    w.workTime = BREAK_AFTER_SECONDS
    w.morale = 50
    local napStart
    for i = 1, 200 do
        run({ w }, self.world, self.jobs, 0.1)
        if w.state == 'breaking' then
            napStart = i
            lu.assertEquals(w:describeState(), 'Napping in a nest')
            lu.assertEquals({ w:tile().x, w:tile().y }, { 7, 2 })
            break
        end
    end
    lu.assertNotNil(napStart, 'never got to bed')
    run({ w }, self.world, self.jobs, BREAK_SECONDS_BED + 0.3)
    lu.assertEquals(w.breaksTaken, 1)
    lu.assertEquals(self.events[#self.events], 'break:bed')
    lu.assertEquals(w.breakAfter, BREAK_AFTER_SECONDS * BED_REST_BONUS)
    lu.assertTrue(w.morale >= 50 + MORALE_BED_BONUS - 1, 'bed should restore morale, got ' .. w.morale)
    lu.assertNil(self.world:get(7, 2).restingBy)
end

function TestWorker:testComplaintsWearMoraleDownUntilTheyQuit()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    local hits = math.ceil(MORALE_MAX / MORALE_COMPLAINT_HIT)
    for _ = 1, hits - 1 do w:complain('test') end
    lu.assertTrue(w.morale > 0 and w.morale <= MORALE_LOW)
    run({ w }, self.world, self.jobs, 0.1)
    lu.assertTrue(w:isWorking(), 'still on staff while morale is above zero')
    local warned = false
    for _, e in ipairs(self.events) do if e == 'lowmorale' then warned = true end end
    lu.assertTrue(warned, 'should warn when morale gets low')
    w.morale = MORALE_COMPLAINT_HIT / 2                      -- one more complaint is the last straw
    w:complain('test')
    lu.assertEquals(w.state, 'quitting')
    run({ w }, self.world, self.jobs, 0.1)
    lu.assertEquals(w.state, 'quitting')
    lu.assertEquals(self.events[#self.events], 'quit:morale')
    lu.assertEquals(self.scoring.quits, 1)
end

function TestWorker:testHungerDrainsMoraleAndFoodRestoresIt()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK))
    self.bush.ready = false; self.bush.timer = 999
    w.hunger = HUNGER_EAT_THRESHOLD - 5
    w.drain = 0
    run({ w }, self.world, self.jobs, 10)
    lu.assertTrue(w.morale < MORALE_MAX - 10, 'hungry morphi should lose morale')
    local low = w.morale
    w.hunger = HUNGER_MAX
    run({ w }, self.world, self.jobs, 10)
    lu.assertTrue(w.morale > low, 'fed morphi should recover')
end

function TestWorker:testOnlyALumberjackBuildsABed()
    self.bush.ready = false; self.bush.timer = 999
    local site = self.world:addSite(SITE_BED, 7, 2)
    self.jobs:postSite(site)
    local forager = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER, 6, 5))
    run({ forager }, self.world, self.jobs, 6)
    lu.assertFalse(self.world:get(7, 2).bed, 'a forager should leave woodwork alone')
    lu.assertTrue(self.jobs:hasJobForSite(site))
    local jack = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_LUMBERJACK, 6, 5))
    local sawTool = false
    for _ = 1, 100 do
        run({ jack }, self.world, self.jobs, 0.1)
        if jack:toolInHand() == 'leaf' then sawTool = true end
        if self.world:get(7, 2).bed then break end
    end
    lu.assertTrue(self.world:get(7, 2).bed, 'lumberjack should build the bed')
    lu.assertTrue(sawTool, 'should carry a saw to the bed site')
    lu.assertNil(jack:toolInHand())
end

function TestWorker:testToolsInHand()
    local jack = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 8, 2))
    self.jobs:postNode(self.tree)
    run({ jack }, self.world, self.jobs, 0.6)
    lu.assertEquals(jack:toolInHand(), 'twigs')
    local miner = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_MINER, 3, 5))
    self.jobs:postNode(self.ore)
    run({ miner }, self.world, self.jobs, 0.6)
    lu.assertEquals(miner:toolInHand(), 'spade')
    local forager = Worker.new(self.world, self.jobs, self.scoring, Rng.new(4), self.opts(ROLE_FORAGER, 2, 3))
    local site = self.world:addSite(SITE_STORAGE, 2, 1)
    self.jobs:postSite(site)
    run({ forager }, self.world, self.jobs, 0.6)
    lu.assertEquals(forager:toolInHand(), 'twigs')
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

function TestWorker:testLeavesWalledOffBushOnTheQueue()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER))
    self.bush.ready = false; self.bush.timer = 999
    self.pocket.ready = true
    self.jobs:postNode(self.pocket)
    run({ w }, self.world, self.jobs, 3)
    lu.assertEquals(#self.complaints, 0)         -- nothing to complain about, it just is not reachable
    lu.assertEquals(self.jobs:count(), 1)        -- and the job is still there
    lu.assertNil(self.pocket.claimedBy)
    lu.assertEquals(self.scoring.output, 0)
    -- dig it open and the forager gets to it
    self.world:dig(4, 7)
    run({ w }, self.world, self.jobs, 15)
    lu.assertEquals(self.scoring.delivered.food, 1)
end
function TestWorker:testPicksTheNearestJobNotTheOldest()
    -- forager at (9,3): the bush at (2,2) was posted first, a new ripe bush at (8,1) is closer
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_FORAGER, 9, 3))
    local close = self.world:addNode(NODE_BUSH, 8, 1); close.ready = true
    self.jobs:postNode(self.bush)
    self.jobs:postNode(close)
    run({ w }, self.world, self.jobs, 0.6)
    lu.assertEquals(w.targetNode, close)
    lu.assertEquals(close.claimedBy, w)
    lu.assertNil(self.bush.claimedBy)
    lu.assertTrue(self.jobs:hasJobFor(self.bush))
end
function TestWorker:testTwoMorphisNeverShareAJob()
    local a = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_LUMBERJACK, 8, 3))
    local b = Worker.new(self.world, self.jobs, self.scoring, Rng.new(3), self.opts(ROLE_LUMBERJACK, 8, 3))
    self.jobs:postNode(self.tree)
    run({ a, b }, self.world, self.jobs, 1)
    local takers = 0
    if a.targetNode == self.tree then takers = takers + 1 end
    if b.targetNode == self.tree then takers = takers + 1 end
    lu.assertEquals(takers, 1)
    lu.assertFalse(self.jobs:hasJobFor(self.tree))
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
    -- at zero it is starving, and holds out as long as a full belly lasts (100 / 2 seconds)
    run({ w }, self.world, self.jobs, 2)
    lu.assertEquals(w:hungerStatus(), 'starving')
    lu.assertTrue(w:isWorking())
    run({ w }, self.world, self.jobs, HUNGER_MAX / 2 - 3)
    lu.assertNotEquals(w.state, 'quitting')
    run({ w }, self.world, self.jobs, 3)
    lu.assertEquals(w.state, 'quitting')
    lu.assertEquals(self.scoring.quits, 1)
    lu.assertFalse(w:isWorking())
    lu.assertEquals(self.events[#self.events], 'quit:starved')
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
    local quitsEarly = nil -- quits in the first 90 s, the season length this test was written for
    while clock < QUARTER_SECONDS + 1 and not ended do
        clock = clock + dt
        if not quitsEarly and clock >= 90 then quitsEarly = scoring.quits end
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
    -- role work comes before build jobs, so the second spot may still be waiting
    lu.assertTrue(world:storageCapacity() >= 1, 'no storage site was built')
    local rs = ''
    for k, v in pairs(reasons) do rs = rs .. k .. '=' .. v .. ' ' end
    print(string.format('  %-14s Q1 unaided seed %s: food %d logs %d gold %d, complaints %d (%s), quits %d, fed %d%%, stored %d, grade %s (%.2fs)',
        DIFFICULTIES[difficultyIndex].name, DEFAULT_SEED, report.food, report.logs, report.gold, report.complaints, rs,
        report.attrition, report.fedPct, world:storedCount(ITEM_FOOD), report.grade, elapsed))
    print(string.format('    stockpile: logs %d gold %d', world.stock.logs, world.stock.gold))
    report.quitsEarly = quitsEarly
    return report
end
function TestSimulation:testFullQuarterOnGeneratedWorld()
    for d = 1, #DIFFICULTIES do
        local report = simulateQuarter(d)
        if d == 2 then
            lu.assertTrue(report.output >= 6, 'morphis delivered only ' .. report.output)
            -- (nobody marks clay here, so no shinies: they are found only by digging)
            lu.assertTrue(report.logs >= 1 and report.food >= 1, 'gatherers and foragers should deliver')
            lu.assertTrue(report.complaints <= 14, 'complaint spam: ' .. report.complaints)
            -- a five-minute season unaided may cost a morphi; the first 90 s must not
            lu.assertTrue(report.quitsEarly == 0, 'quits in 90 s with nobody helping: ' .. tostring(report.quitsEarly))
        end
    end
end

-- Free play tastes: loves one food, hates one, eats the rest.
TestWilds = {}
function TestWilds:setUp()
    self.world = World.fromGrid(GRID, Rng.new(1))
    self.jobs = Jobs.new()
    self.scoring = Scoring.new(1)
    self.complaints = {}
    self.opts = function(role, sheet)
        return {
            x = 5, y = 4, role = role, sheet = sheet, name = 'Dave', drain = 0.5, wilds = true,
            onComplain = function(w, reason, node) self.complaints[#self.complaints + 1] = { reason = reason, node = node, why = w.boredReason } end,
        }
    end
end

function TestWilds:testTastes()
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), self.opts(ROLE_FORAGER, 'pupper'))
    lu.assertEquals(w.diet, 'steak')
    lu.assertEquals(w.hates, 'grapes')
    lu.assertTrue(w:willEat('steak'))
    lu.assertTrue(w:willEat('fish'))
    lu.assertFalse(w:willEat('grapes'))
    w.hunger = HUNGER_STARVING - 1
    lu.assertTrue(w:willEat('grapes'), 'starving, it eats even what it hates')
    -- a loved meal fills more and cheers; a hated one fills little and does not
    w.hunger, w.morale = 10, 50
    w:mealOf('steak')
    lu.assertEquals(w.hunger, 10 + FOOD_VALUE.loved)
    lu.assertEquals(w.morale, 50 + MORALE_LOVED_MEAL)
    w.hunger = 10
    w:mealOf('fish')
    lu.assertEquals(w.hunger, 10 + FOOD_VALUE.fine)
    w.hunger, w.morale = 5, 50
    w:mealOf('grapes')
    lu.assertEquals(w.hunger, 5 + FOOD_VALUE.hated)
    lu.assertEquals(w.morale, 50 - MORALE_HATED_MEAL)
    -- survival levels keep one food
    local s = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), { x = 5, y = 4, sheet = 'pupper' })
    lu.assertFalse(s:willEat('fish'))
end

function TestWilds:testNothingToDoIsAHardship()
    -- a forager with nothing posted to pick stands about, gets bored and says why
    -- (this map has storage, so it is the bushes that are out of reach)
    local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), self.opts(ROLE_FORAGER, 'pupper'))
    w.hunger = HUNGER_MAX
    local before = w.morale
    run({ w }, self.world, self.jobs, BORED_SECONDS + 4)
    lu.assertTrue(#self.complaints >= 1)
    lu.assertEquals(self.complaints[1].reason, 'bored')
    lu.assertEquals(self.complaints[1].why, 'reach')
    lu.assertTrue(w.morale < before, 'boredom costs morale, and standing about does not win it back')
end

function TestWilds:testBushesWearOutInTheWilds()
    local bush = self.world:get(2, 2).node
    self.world.wilds = true
    for _ = 1, BUSH_PICKINGS - 1 do bush.ready = true; self.world:harvestNode(bush) end
    lu.assertNotNil(self.world:get(2, 2).node)
    bush.ready = true
    self.world:harvestNode(bush)
    lu.assertNil(self.world:get(2, 2).node, 'withered after its last picking')
end

function TestWilds:testTradeAtCamp()
    -- a steak and a chili in storage: each partner's loved food, so two gifts
    self.world:storeItem(ITEM_FOOD, 4, 4, 'steak')
    self.world:storeItem(ITEM_FOOD, 7, 4, 'chili')
    self.world.stock.gold = 1
    local a = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), self.opts(ROLE_FORAGER, 'pupper'))
    local b = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER, 'cwab'))
    a.hunger, b.hunger, a.morale, b.morale = 60, 60, 30, 40
    -- a finishes a rest feeling low and offers a trade
    a.state = 'breaking'
    a:finishAction()
    lu.assertEquals(a.state, 'trading')
    lu.assertNotNil(self.world.openTrade)
    -- b, standing about at camp, takes it up: the gold is staked
    run({ a, b }, self.world, self.jobs, 1)
    lu.assertEquals(b.state, 'trading')
    lu.assertEquals(self.world.stock.gold, 0)
    lu.assertEquals(a.trade.gifts, 2)
    -- hunger is on hold while they talk; they eat together halfway
    run({ a, b }, self.world, self.jobs, TRADE_SECONDS / 2 - 3)
    lu.assertEquals(a.hunger, 60)
    lu.assertEquals(#self.world.items, 2)
    run({ a, b }, self.world, self.jobs, 6)
    lu.assertEquals(#self.world.items, 0)
    lu.assertEquals(a.hunger, math.min(HUNGER_MAX, 60 + FOOD_VALUE.loved))
    -- and close the deal: happy thoughts, more for the gifts
    run({ a, b }, self.world, self.jobs, TRADE_SECONDS / 2)
    lu.assertEquals(a.state ~= 'trading', true)
    -- (a fed morphi also cheers up a little in the seconds around the trade)
    lu.assertTrue(a.morale >= math.min(MORALE_MAX, 30 + MORALE_BREAK_BONUS + MORALE_LOVED_MEAL + MORALE_TRADE_BASE + 2 * MORALE_GIFT))
    lu.assertTrue(b.morale >= math.min(MORALE_MAX, 40 + MORALE_LOVED_MEAL + MORALE_TRADE_BASE + 2 * MORALE_GIFT))
end

function TestWilds:testNoTradeWithoutFood()
    self.world.stock.gold = 1
    local a = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), self.opts(ROLE_FORAGER, 'pupper'))
    local b = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), self.opts(ROLE_MINER, 'cwab'))
    a.morale, b.morale = 30, 40
    a.state = 'breaking'
    a:finishAction()
    run({ a, b }, self.world, self.jobs, 2)
    lu.assertNotEquals(b.state, 'trading')
    lu.assertEquals(self.world.stock.gold, 1, 'nothing staked without a meal for both')
    run({ a, b }, self.world, self.jobs, TRADE_WAIT_SECONDS)
    lu.assertNil(self.world.openTrade, 'the offer lapses')
    lu.assertNotEquals(a.state, 'trading')
end





-- Fun together: once a season a morphi may play with another. Talk, no gold,
-- no meals, and a lift for both at the end.
TestPlay = {}
function TestPlay:setUp()
    self.world = World.fromGrid(GRID, Rng.new(1))
    self.jobs = Jobs.new()
    self.scoring = Scoring.new(1)
    self.complaints, self.events = {}, {}
    self.make = function(name, x, y, sheet)
        local w = Worker.new(self.world, self.jobs, self.scoring, Rng.new(#name + (x or 5) * 7), {
            x = x or 5, y = y or 4, role = ROLE_MINER, sheet = sheet or 'cwab', name = name, drain = 0.5, wilds = true, hunger = 90,
            onComplain = function(_, reason) self.complaints[#self.complaints + 1] = reason end,
            onEvent = function(w, ev, data) self.events[#self.events + 1] = { who = w, name = ev, data = data } end,
        })
        w.funAt = 0 -- due for some fun, unless a test says otherwise
        return w
    end
    self.played = function()
        local list = {}
        for _, e in ipairs(self.events) do if e.name == 'play' then list[#list + 1] = e end end
        return list
    end
end

function TestPlay:testFunComesAtRandomAboutOncePerSeason()
    local a, b, c = self.make('Pip'), self.make('Dave', 6, 4), self.make('Gus', 6, 5)
    lu.assertTrue(a:hasPlayChance())
    lu.assertTrue(a:offerPlay())
    lu.assertTrue(b:joinPlay())
    lu.assertFalse(a:hasPlayChance(), 'having fun sets the next one a while off')
    lu.assertFalse(b:hasPlayChance())
    -- the gap is a half to one and a half seasons, drawn at random
    local lo, hi = math.huge, 0
    for i = 1, 200 do
        local w = self.make('Pip', 5, 4)
        w.rng = Rng.new(i * 7919)
        local gap = w:nextFunGap()
        lo, hi = math.min(lo, gap), math.max(hi, gap)
    end
    lu.assertTrue(lo >= PLAY_MEAN_SECONDS * 0.5 and hi <= PLAY_MEAN_SECONDS * 1.5)
    lu.assertTrue(hi - lo > PLAY_MEAN_SECONDS * 0.5, 'a spread, not one fixed gap')
    -- a is not due again until its gap has passed
    a:endPlay(true)
    lu.assertFalse(a:offerPlay())
    a.clock = a.funAt
    lu.assertTrue(a:hasPlayChance())
    -- an offer nobody takes does not spend the fun
    lu.assertTrue(c:offerPlay())
    c:endPlay(false)
    lu.assertTrue(c:hasPlayChance())
end

function TestPlay:testAnOfferIsJoinedByAFreeMorphiNotAHungryOne()
    local a = self.make('Pip')
    local hungry = self.make('Hank', 6, 4)
    hungry.hunger = HUNGER_EAT_THRESHOLD - 5
    -- a rest just over at camp: a natural break, and a has its chance
    a.state = 'breaking'
    a:finishAction()
    lu.assertEquals(a.state, 'playing')
    lu.assertEquals(self.world.openPlay, a.play)
    lu.assertNil(self.world.openTrade, 'its own offer, not a trade')
    lu.assertEquals(Stats.bucket(a), 'idle', 'waiting for somebody is still standing about')
    lu.assertFalse(hungry:joinPlay())
    run({ a, hungry }, self.world, self.jobs, 1)
    lu.assertNil(hungry.play)
    lu.assertNil(a.play.b)
    -- a free, fed morphi standing about at camp joins
    local b = self.make('Dave', 6, 5)
    run({ a, hungry, b }, self.world, self.jobs, 1)
    lu.assertEquals(a.play.b, b)
    lu.assertEquals(b.play, a.play)
    lu.assertNil(self.world.openPlay)
    lu.assertNil(hungry.play)
end

function TestPlay:testAnOfferNobodyTakesLapses()
    local a = self.make('Pip')
    lu.assertTrue(a:offerPlay())
    run({ a }, self.world, self.jobs, PLAY_WAIT_SECONDS + 1)
    lu.assertNil(a.play)
    lu.assertNil(self.world.openPlay)
    lu.assertNotEquals(a.state, 'playing')
    lu.assertTrue(a:hasPlayChance())
    lu.assertEquals(#self.played(), 0)
end

function TestPlay:testATalkLineByLineThenALiftForBoth()
    -- no gold and no food anywhere: playing needs neither
    self.world.stock.gold = 0
    lu.assertEquals(#self.world.items, 0)
    local a, b = self.make('Pip'), self.make('Dave', 7, 6)
    a.morale, b.morale = 35, 40
    a.idleSince = -100 -- it had been standing about
    lu.assertFalse(a:offerTrade(), 'a trade needs gold')
    lu.assertTrue(a:offerPlay())
    lu.assertTrue(b:joinPlay())
    local pl = a.play
    lu.assertEquals(#pl.convo, 12)
    lu.assertNotNil(PLAY_CHAT[pl.category])
    local said, last = {}, { [a] = a.bubble, [b] = b.bubble }
    local dt, clock, endAt = 0.05, 0, nil
    while clock < 70 and not endAt do
        clock = clock + dt
        local before = { [a] = a.morale, [b] = b.morale }
        a:update(dt, clock)
        b:update(dt, clock)
        for _, w in ipairs({ a, b }) do
            if w.bubble and w.bubble ~= last[w] and w.bubble.text ~= 'sure!' then
                said[#said + 1] = { who = w, text = w.bubble.text, at = clock, ttl = w.bubble.ttl }
            end
            last[w] = w.bubble
        end
        if a.play then
            -- playing is fun: not idle, not bored
            lu.assertEquals(Stats.bucket(a), 'rest')
            lu.assertEquals(Stats.bucket(b), 'rest')
        else
            endAt = clock
            -- the lift, on top of the little a fed morphi recovers in a step
            for _, w in ipairs({ a, b }) do
                lu.assertAlmostEquals(w.morale - before[w], MORALE_PLAY + MORALE_RECOVER * dt, 0.01)
            end
        end
    end
    lu.assertNotNil(endAt, 'the talk never ended')
    -- twelve lines, A then B, a line every few seconds
    lu.assertEquals(#said, 12)
    for i, s in ipairs(said) do
        lu.assertEquals(s.text, pl.convo[i])
        lu.assertIs(s.who, i % 2 == 1 and a or b)
        lu.assertTrue(math.abs(s.ttl - PLAY_BUBBLE_SECONDS) < 0.1)
        if i > 1 then lu.assertAlmostEquals(s.at - said[i - 1].at, PLAY_LINE_SECONDS, 0.06) end
    end
    lu.assertAlmostEquals(endAt - said[1].at, 12 * PLAY_LINE_SECONDS, 0.11)
    -- both back to their day, with nobody grumbling and nothing spent
    lu.assertNil(a.play)
    lu.assertNil(b.play)
    lu.assertNotEquals(a.state, 'playing')
    lu.assertNotEquals(b.state, 'playing')
    lu.assertEquals(#self.complaints, 0)
    lu.assertEquals(self.world.stock.gold, 0)
    lu.assertEquals(#self.world.items, 0)
    -- and it is news: who, and what kind of play
    local played = self.played()
    lu.assertEquals(#played, 1)
    lu.assertIs(played[1].who, a)
    lu.assertIs(played[1].data.partner, b)
    lu.assertEquals(played[1].data.category, pl.category)
    lu.assertEquals(played[1].data.title, pl.convo.title)
end

function TestPlay:testTheJoinerWalksOverToTalk()
    local a, b = self.make('Pip'), self.make('Dave', 9, 1)
    lu.assertTrue(a:offerPlay())
    lu.assertTrue(b:joinPlay())
    lu.assertEquals(b.state, 'walking')
    lu.assertEquals(b.goal, 'play')
    lu.assertEquals(Stats.bucket(b), 'rest')
    run({ a, b }, self.world, self.jobs, 4)
    lu.assertEquals(b.state, 'playing')
    local at, bt = a:tile(), b:tile()
    lu.assertTrue(math.abs(at.x - bt.x) <= 1 and math.abs(at.y - bt.y) <= 1, 'beside each other')
    lu.assertTrue(a.play.lines >= 1, 'the talk began')
end

function TestPlay:testAMorphiThatLeavesGetsNoLift()
    local a, b = self.make('Pip'), self.make('Dave', 6, 5)
    a.morale, b.morale = 50, 50
    a:offerPlay()
    b:joinPlay()
    run({ a, b }, self.world, self.jobs, 10)
    lu.assertNotNil(a.play)
    -- b gets hungry: it goes to eat, the talk is over and nobody is lifted
    b.hunger = HUNGER_EAT_THRESHOLD - 1
    local aBefore, bBefore = a.morale, b.morale
    run({ a, b }, self.world, self.jobs, 0.1)
    lu.assertNil(a.play)
    lu.assertNil(b.play)
    lu.assertNil(self.world.openPlay)
    lu.assertTrue(b.morale <= bBefore, 'no lift for the one who left')
    lu.assertTrue(a.morale < aBefore + MORALE_PLAY)
    lu.assertNotEquals(a.state, 'playing')
    lu.assertNotEquals(b.state, 'playing')
    -- one quits mid-talk: the same
    local c, d = self.make('Gus', 5, 5), self.make('Rex', 6, 4)
    c:offerPlay()
    d:joinPlay()
    run({ c, d }, self.world, self.jobs, 5)
    lu.assertNotNil(c.play)
    local cBefore = c.morale
    d:quit('morale')
    lu.assertNil(c.play)
    lu.assertNil(d.play)
    lu.assertEquals(c.morale, cBefore)
    lu.assertEquals(c.state, 'idle')
    lu.assertEquals(#self.played(), 0)
end

function TestPlay:testTradeAndPlayKeepTheirOwnOffers()
    self.world:storeItem(ITEM_FOOD, 4, 4, 'steak')
    self.world:storeItem(ITEM_FOOD, 7, 4, 'chili')
    self.world.stock.gold = 1
    local a, b, c = self.make('Pip', 5, 4, 'pupper'), self.make('Dave', 6, 4, 'cwab'), self.make('Gus', 5, 5)
    lu.assertTrue(c:offerPlay())
    lu.assertNil(self.world.openTrade)
    a.morale = 30
    a.state = 'breaking'
    a:finishAction()
    lu.assertEquals(a.state, 'trading', 'feeling low with gold about: a trade, as before')
    lu.assertEquals(self.world.openTrade, a.trade)
    lu.assertEquals(self.world.openPlay, c.play)
    lu.assertTrue(b:joinTrade())
    lu.assertEquals(self.world.stock.gold, 0)
    lu.assertEquals(a.trade.gifts, 2)
    lu.assertEquals(self.world.openPlay, c.play, 'the offer to play is still open')
    lu.assertFalse(a:joinPlay(), 'busy trading')
    lu.assertFalse(b:joinPlay())
end

function TestPlay:testPlayNowPairsTheNearestTwoWhateverTheGap()
    local a, b, c = self.make('Pip', 2, 3), self.make('Dave', 9, 3), self.make('Gus', 7, 3)
    local hungry = self.make('Hank', 9, 3)
    hungry.hunger = 5
    for _, w in ipairs({ a, b, c, hungry }) do w.funAt = 1e9 end
    lu.assertNil(Worker.playNow({ a, hungry }), 'one free morphi is not two')
    local pl = Worker.playNow({ a, b, c, hungry })
    lu.assertNotNil(pl, 'being not due does not stop PLAY NOW')
    lu.assertTrue((pl.a == b and pl.b == c) or (pl.a == c and pl.b == b))
    lu.assertNil(a.play)
    lu.assertNil(hungry.play)
    lu.assertEquals(b.funAt, 1e9, 'a tester start does not move the next fun')
    run({ a, b, c, hungry }, self.world, self.jobs, 1)
    lu.assertTrue(pl.lines >= 1)
    lu.assertNotNil(pl.a.bubble or pl.b.bubble)
end

function TestPlay:testTheTestersPickOfTwoMorphisAndAKindOfFun()
    local a, b, c = self.make('Pip', 4, 4), self.make('Dave', 8, 4), self.make('Gus', 6, 6)
    for _, kind in ipairs(PLAY_CATEGORIES) do
        local x, y = self.make('X' .. kind, 4, 4), self.make('Y' .. kind, 8, 4)
        local pl = Worker.playPair(x, y, kind)
        lu.assertNotNil(pl)
        lu.assertEquals(pl.category, kind)
        lu.assertEquals(#pl.convo, 12)
        lu.assertEquals(x.play, pl)
        lu.assertEquals(y.play, pl)
        lu.assertStrContains(x:describeState(), PLAY_DOING[kind]:gsub('%s+$', ''))
    end
    lu.assertNil(Worker.playPair(a, a, 'dance'), 'two different morphis')
    lu.assertNil(Worker.playPair(a, nil, 'dance'))
    b.hunger = 5
    lu.assertNil(Worker.playPair(a, b, 'dance'), 'a hungry one cannot')
    a:quit('morale')
    lu.assertNil(Worker.playPair(a, c, 'dance'), 'nor one that is leaving')
    -- the pair is lifted at the end, like any other play
    local p, q = self.make('Pip2', 4, 4), self.make('Dave2', 5, 4)
    p.morale, q.morale = 40, 40
    p.funAt, q.funAt = 1e9, 1e9
    local pl = Worker.playPair(p, q, 'dance')
    run({ p, q }, self.world, self.jobs, 12 * PLAY_LINE_SECONDS + 10)
    lu.assertNil(p.play)
    lu.assertTrue(p.morale > 40 + MORALE_PLAY - 5)
    local played = self.played()
    lu.assertEquals(played[#played].data.category, 'dance')
    lu.assertEquals(played[#played].data.title, pl.convo.title)
end

function TestPlay:testTheTalkComesFromTheSeededRng()
    local function pick(seed)
        local world = World.fromGrid(GRID, Rng.new(1))
        local rng = Rng.new(seed)
        local a = Worker.new(world, Jobs.new(), self.scoring, rng, { x = 5, y = 4, wilds = true, hunger = 90 })
        local b = Worker.new(world, Jobs.new(), self.scoring, rng, { x = 6, y = 4, wilds = true, hunger = 90 })
        a.funAt, b.funAt = 0, 0
        a:offerPlay()
        b:joinPlay()
        return a.play.category .. '/' .. a.play.convo.title
    end
    lu.assertEquals(pick(42), pick(42))
    local seen, n = {}, 0
    for s = 1, 80 do
        local k = pick(s)
        if not seen[k] then seen[k] = true; n = n + 1 end
    end
    lu.assertEquals(n, 6, 'all six talks turn up')
end

function TestPlay:testDetailsShowWhatItCarriesAndTheTalkSoFar()
    local a, b = self.make('Pip'), self.make('Dave', 6, 5)
    a.slots[SLOT_WORK] = { kind = 'logs' }
    local d = a:details()
    lu.assertStrContains(d.lines[1].text, 'Carrying: sticks')
    a.slots[SLOT_WORK] = nil
    a:offerPlay()
    b:joinPlay()
    run({ a, b }, self.world, self.jobs, 3 * PLAY_LINE_SECONDS + 1)
    d = a:details()
    lu.assertEquals(d.title, 'Pip')
    lu.assertStrContains(d.state, 'with')
    local said = {}
    for _, l in ipairs(d.lines) do if l.who then said[#said + 1] = l end end
    lu.assertTrue(#said >= 3 and #said <= 4)
    lu.assertEquals(said[1].text, a.play.convo[1])
    lu.assertIs(said[1].who, a)
    lu.assertIs(said[2].who, b)
    lu.assertEquals(b:details().lines[#b:details().lines].text, said[#said].text, 'both see the same talk')
end

function TestPlay:testEveryFunIsAnnouncedAtStartAndEnd()
    local a, b = self.make('Pip'), self.make('Dave', 6, 5)
    a:offerPlay()
    b:joinPlay()
    local starts = 0
    for _, e in ipairs(self.events) do if e.name == 'playstart' then starts = starts + 1 end end
    lu.assertEquals(starts, 1)
    run({ a, b }, self.world, self.jobs, 12 * PLAY_LINE_SECONDS + 10)
    lu.assertEquals(#self.played(), 1)
    -- one cut short is announced too
    local c, d = self.make('Gus', 5, 5), self.make('Rex', 6, 4)
    c:offerPlay()
    d:joinPlay()
    run({ c, d }, self.world, self.jobs, 6)
    d.hunger = HUNGER_EAT_THRESHOLD - 1
    run({ c, d }, self.world, self.jobs, 0.2)
    local cut = 0
    for _, e in ipairs(self.events) do if e.name == 'playcut' then cut = cut + 1 end end
    lu.assertEquals(cut, 1)
end

function TestPlay:testNoPlayOutsideFreePlay()
    local world = World.fromGrid(GRID, Rng.new(1))
    world.arcade = true
    local a = Worker.new(world, self.jobs, self.scoring, Rng.new(1), { x = 5, y = 4 })
    local b = Worker.new(world, self.jobs, self.scoring, Rng.new(2), { x = 6, y = 4 })
    lu.assertFalse(a:hasPlayChance())
    lu.assertFalse(a:offerPlay())
    lu.assertNil(Worker.playNow({ a, b }))
    -- nor on a survival level
    local s1 = Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), { x = 5, y = 4, hunger = 90 })
    local s2 = Worker.new(self.world, self.jobs, self.scoring, Rng.new(2), { x = 6, y = 4, hunger = 90 })
    lu.assertFalse(s1:offerPlay())
    lu.assertNil(Worker.playNow({ s1, s2 }))
end

function TestPlay:testEveryLineFitsTheBubble()
    for _, cat in ipairs(PLAY_CATEGORIES) do
        lu.assertTrue(#PLAY_CHAT[cat] >= 1)
        for _, convo in ipairs(PLAY_CHAT[cat]) do
            lu.assertNotNil(convo.title)
            lu.assertEquals(#convo, 12)
            for _, line in ipairs(convo) do lu.assertTrue(#line <= 18, line) end
        end
    end
end

os.exit(lu.LuaUnit.run())
