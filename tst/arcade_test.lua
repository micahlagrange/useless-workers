local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')
local World = require('src.world')
local Abilities = require('src.abilities')
local Campaign = require('src.campaign')

local DT = 1 / 30

local function spawn(run, jobs, scoring)
    local workers = {}
    for i, spec in ipairs(run.specs) do
        workers[#workers + 1] = Worker.new(run.world, jobs, scoring, Rng.new(i), {
            x = spec.x, y = spec.y, role = spec.role, sheet = spec.sheet, name = spec.name, diet = spec.diet,
        })
    end
    return workers
end

-- Plays an arcade level with the real morphi AI after laying down a
-- solution, until everyone has eaten or the cap runs out. Returns whether
-- they all ate, the points spent, and how long it took.
local function play(index, solutionName, cap, difficulty)
    local run = Campaign.load(index, Rng.new(index), 'arcade', difficulty)
    local world, def = run.world, run.def
    local jobs = Jobs.new()
    for _, node in ipairs(world.nodes) do
        if node.ready then jobs:postNode(node) end
    end
    local scoring = Scoring.new(2)
    local abilities = Abilities.new(world, jobs, function() end)
    if solutionName then
        local ok, why = Campaign.apply(def[solutionName], abilities)
        lu.assertTrue(ok, 'arcade ' .. index .. ' ' .. solutionName .. ': ' .. tostring(why))
    end
    local workers = spawn(run, jobs, scoring)
    local clock = 0
    while clock < (cap or 240) and not Campaign.allAte(workers) do
        clock = clock + DT
        jobs:update(DT)
        world:update(DT, function(n) jobs:postNode(n) end)
        for _, w in ipairs(workers) do w:update(DT, clock) end
    end
    return Campaign.allAte(workers), world.spent, clock, workers, run
end

TestArcadeLevels = {}
function TestArcadeLevels:testSixWellFormedLevels()
    lu.assertEquals(Campaign.count('arcade'), 6)
    lu.assertEquals(Campaign.count(), 5) -- survival untouched
    local seen = {}
    for i = 1, 6 do
        local def = Campaign.arcade[i]
        local ok, why = Campaign.validate(def, 'arcade')
        lu.assertTrue(ok, 'arcade ' .. i .. ': ' .. tostring(why))
        for _, m in ipairs(def.morphis) do seen[m] = true end
        local run = Campaign.load(i, Rng.new(i), 'arcade')
        lu.assertTrue(run.world.arcade)
        lu.assertEquals(run.set, 'arcade')
        lu.assertEquals(#run.specs, #def.morphis)
        lu.assertEquals(run.world.stock.logs, def.points.easy)
        lu.assertEquals(Campaign.load(i, Rng.new(i), 'arcade', 3).world.stock.logs, def.points.hard)
        lu.assertTrue(def.points.easy >= def.points.normal and def.points.normal >= def.points.hard)
        for _, spec in ipairs(run.specs) do
            lu.assertEquals(spec.role, ARCADE_ROLE[spec.species])
            lu.assertTrue(run.world:isReachable(spec.x, spec.y), 'spawn off the camp bank in arcade ' .. i)
        end
    end
    for _, species in ipairs({ 'pupper', 'woofoof', 'twins', 'cwab', 'blue' }) do
        lu.assertTrue(seen[species], species .. ' never shows up')
    end
    -- each level asks for everything the one before did, and then some
    local last = 0
    for i = 1, 6 do
        local n = 0
        for _ in pairs(Campaign.arcade[i].needs) do n = n + 1 end
        lu.assertTrue(n >= last, 'arcade ' .. i .. ' asks for less than the level before')
        last = n
    end
end

function TestArcadeLevels:testArcadeMorphisHaveOneJobEach()
    lu.assertEquals(ARCADE_ROLE.twins, ROLE_BUILDER)
    lu.assertEquals(ROLES.builder.jobType, 'build')
    for species, role in pairs(ARCADE_ROLE) do
        lu.assertNotNil(ROLES[role], species .. ' has role ' .. role)
    end
end

-- The obvious build fits the hard budget, with a log or two left over, and
-- easy pays for it twice: a heap of mistakes still wins.
function TestArcadeLevels:testObviousSolutionsFeedEveryoneOnHard()
    for i = 1, 6 do
        local allAte, spent, clock = play(i, 'obvious', nil, 3)
        print(string.format('  arcade %d obvious: spent %d, fed in %ds', i, spent, math.floor(clock)))
        lu.assertTrue(allAte, 'arcade ' .. i .. ': not everyone ate on the obvious solution')
        local p = Campaign.arcade[i].points
        lu.assertTrue(spent <= p.hard, 'arcade ' .. i .. ' obvious solution does not fit the hard budget')
        lu.assertTrue(p.easy >= spent * 2, 'arcade ' .. i .. ' easy should pay for the obvious build twice')
    end
end

-- The clever build beats par: three stars and then some.
function TestArcadeLevels:testCleverSolutionsBeatPar()
    for i = 1, 6 do
        local allAte, spent, clock = play(i, 'clever')
        print(string.format('  arcade %d clever:  spent %d, par %d, fed in %ds', i, spent, Campaign.arcade[i].par, math.floor(clock)))
        lu.assertTrue(allAte, 'arcade ' .. i .. ': not everyone ate on the clever solution')
        local par = Campaign.arcade[i].par
        lu.assertTrue(spent <= par, 'arcade ' .. i .. ' clever solution is over par')
        if par > 0 then lu.assertTrue(spent < par, 'arcade ' .. i .. ' clever solution should come in under par') end
    end
end

function TestArcadeLevels:testNobodyEatsBeforeTheNeedsAreMet()
    -- level 2 with no bridge: the food is out of reach, nobody eats, nobody leaves
    local allAte, _, _, workers = play(2, nil, 40)
    lu.assertFalse(allAte)
    for _, w in ipairs(workers) do
        lu.assertTrue(w.alive)
        lu.assertEquals(w.hunger, HUNGER_MAX)
    end
    -- level 3 with no bin: food within reach, but they are picky
    allAte, _, _, workers = play(3, nil, 40)
    lu.assertFalse(allAte)
    lu.assertEquals(Campaign.ateCount(workers), 0)
end

function TestArcadeLevels:testGoalChecklistTicksLive()
    local run = Campaign.load(6, Rng.new(6), 'arcade')
    local workers = spawn(run, Jobs.new(), Scoring.new(2))
    local goals = Campaign.goals(run, workers)
    lu.assertEquals(#goals, 5)
    for _, g in ipairs(goals) do lu.assertFalse(g.done, g.label) end
    local world = run.world
    world:markStorage(7, 5, STORAGE_BIN_CAPACITY)
    goals = Campaign.goals(run, workers)
    lu.assertTrue(goals[1].done)   -- a bin
    lu.assertFalse(goals[2].done)  -- floors
    for _, f in ipairs(run.def.clever.floor) do world:markFloor(f[1], f[2]) end
    goals = Campaign.goals(run, workers)
    lu.assertTrue(goals[2].done)
    lu.assertFalse(goals[3].done)  -- the gap is open
    world:setType(5, 6, TILE_WALL)
    world:setType(6, 6, TILE_DOOR)
    goals = Campaign.goals(run, workers)
    lu.assertTrue(goals[3].done)
    lu.assertTrue(goals[4].done)   -- the bin at 7,5 is inside
    lu.assertFalse(goals[5].done)
    workers[1].ate = true
    goals = Campaign.goals(run, workers)
    lu.assertStrContains(goals[5].label, '1/5')
end

TestEnclosure = {}
function TestEnclosure:setUp()
    -- a hut of walls with a door, floors inside, a bin inside and one outside
    self.world = World.fromGrid({
        '..........',
        '..WWWW....',
        '..W..W....',
        '..W..D.BB.',
        '..WWWW.BB.',
        '..........',
    }, Rng.new(1))
    self.world.arcade = true
end

function TestEnclosure:testWallsBlockAndDoorsPass()
    lu.assertFalse(self.world:isPassable(3, 2))
    lu.assertTrue(self.world:isPassable(6, 4))
    lu.assertTrue(self.world:isReachable(4, 3), 'inside the hut through the door')
end

function TestEnclosure:testFloorsInAHutAreEnclosedOnlyWithADoor()
    local w = self.world
    lu.assertFalse(w:floorsEnclosed(), 'no floors yet')
    w:markFloor(4, 3)
    w:markFloor(5, 3)
    lu.assertTrue(w:enclosure().enclosed)
    lu.assertTrue(w:floorsEnclosed())
    -- brick up the door: enclosed, but nobody can get in, so it does not count
    w:setType(6, 4, TILE_WALL)
    lu.assertTrue(w:enclosure().enclosed)
    lu.assertFalse(w:floorsEnclosed())
    -- knock a hole in the wall instead: the fill reaches the map edge
    w:setType(6, 4, TILE_DOOR)
    w:setType(4, 2, TILE_GRASS)
    lu.assertFalse(w:enclosure().enclosed)
    lu.assertFalse(w:floorsEnclosed())
end

function TestEnclosure:testFloorOnTheEdgeIsNeverEnclosed()
    local w = self.world
    w:markFloor(1, 1)
    lu.assertFalse(w:enclosure().enclosed)
end

function TestEnclosure:testBinsInsideCountsOnlyBinsBehindTheWalls()
    local w = self.world
    w:markFloor(4, 3)
    w:markStorage(5, 4, STORAGE_BIN_CAPACITY)
    lu.assertTrue(w:binsInside())
    w:markStorage(8, 2, STORAGE_BIN_CAPACITY)
    lu.assertEquals(w:binCount(), 2)
    lu.assertEquals(w:binsInsideCount(), 1)
    lu.assertFalse(w:binsInside())
end

function TestEnclosure:testStoneAndWaterCountAsWalls()
    local w = World.fromGrid({
        '..........',
        '..###.....',
        '..#.#.BB..',
        '..#~#.BB..',
        '..#.#.....',
        '..#D#.....',
        '..........',
    }, Rng.new(1))
    w.arcade = true
    w:markFloor(4, 3)
    w:markFloor(4, 5)
    lu.assertTrue(w:enclosure().enclosed, 'stone and water bound the fill')
    lu.assertFalse(w:isReachable(4, 3), 'the water splits the room; the top floor is cut off')
    lu.assertFalse(w:floorsEnclosed(), 'a floor nobody can walk to does not count')
    w:setType(4, 4, TILE_GRASS)
    lu.assertTrue(w:floorsEnclosed())
end

function TestEnclosure:testNeedsGateEating()
    local w = self.world
    w.arcadeNeeds = { bins = true, floors = true, enclosed = true, binsInside = true }
    w.arcadePopulation = 2
    lu.assertFalse(w:arcadeReady())
    w:markStorage(5, 4, STORAGE_BIN_CAPACITY)
    lu.assertFalse(w:arcadeReady())
    w:markFloor(4, 3)
    lu.assertFalse(w:arcadeReady(), 'one floor for two morphis')
    w:markFloor(5, 3)
    lu.assertTrue(w:arcadeReady())
    w.arcadeNeeds = {}
    lu.assertTrue(w:arcadeReady())
end

TestArcadeWorker = {}
function TestArcadeWorker:setUp()
    self.world = World.fromGrid({
        '............',
        '..BB...k....',
        '..BB........',
        '......c.....',
        '............',
        '............',
    }, Rng.new(1))
    self.world.arcade = true
    self.world.stock = { logs = 10, gold = 0 }
    self.jobs = Jobs.new()
    for _, n in ipairs(self.world.nodes) do self.jobs:postNode(n) end
    self.scoring = Scoring.new(2)
    self.abilities = Abilities.new(self.world, self.jobs, function() end)
    self.make = function(species, x, y)
        return Worker.new(self.world, self.jobs, self.scoring, Rng.new(1), {
            x = x, y = y, role = ARCADE_ROLE[species], sheet = species,
        })
    end
end

function TestArcadeWorker:run(workers, seconds)
    local clock = 0
    while clock < seconds do
        clock = clock + DT
        self.jobs:update(DT)
        self.world:update(DT, function(n) self.jobs:postNode(n) end)
        for _, w in ipairs(workers) do w:update(DT, clock) end
    end
end

function TestArcadeWorker:testEatsAnyFoodOnceAndNeverGetsHungry()
    local pupper = self.make('pupper', 4, 3)
    self:run({ pupper }, 20)
    lu.assertTrue(pupper.ate)
    lu.assertEquals(pupper.hunger, HUNGER_MAX)
    lu.assertEquals(self.world:readyNodeCount(NODE_BUSH), 1, 'one bush was eaten off')
    self:run({ pupper }, 30)
    lu.assertEquals(self.world:readyNodeCount(NODE_BUSH), 2, 'bushes ripen again and nobody eats twice')
    lu.assertEquals(pupper.breaksTaken, 0)
    lu.assertEquals(pupper.morale, MORALE_MAX)
end

function TestArcadeWorker:testOnlyTheBuilderBuilds()
    self.abilities:select(ABILITY_WALL)
    lu.assertTrue(self.abilities:use(8, 4))
    local pupper = self.make('pupper', 4, 3)
    self:run({ pupper }, 15)
    lu.assertEquals(self.world:get(8, 4).type, TILE_GRASS, 'a forager does not build')
    lu.assertEquals(self.jobs:count('build'), 1)
    local twins = self.make('twins', 4, 4)
    self:run({ pupper, twins }, 15)
    lu.assertEquals(self.world:get(8, 4).type, TILE_WALL)
    lu.assertTrue(twins.ate)
end

function TestArcadeWorker:testPickyMorphisWaitForABin()
    self.world.arcadeNeeds = { bins = true }
    local pupper = self.make('pupper', 4, 3)
    self:run({ pupper }, 10)
    lu.assertFalse(pupper.ate)
    lu.assertEquals(pupper:describeState(), 'Waiting to eat')
    self.abilities:select(ABILITY_BIN)
    lu.assertTrue(self.abilities:use(5, 5))
    local twins = self.make('twins', 4, 4)
    self:run({ pupper, twins }, 40)
    lu.assertTrue(pupper.ate, 'the forager filled the bin and ate from it')
    lu.assertTrue(twins.ate)
end

function TestArcadeWorker:testFloorIsLivingSpaceNotStorage()
    self.abilities:select(ABILITY_STORAGE)
    lu.assertTrue(self.abilities:use(5, 5))
    lu.assertEquals(self.world.stock.logs, 10, 'floors are free')
    local twins = self.make('twins', 4, 4)
    self:run({ twins }, 15)
    lu.assertEquals(#self.world.floors, 1)
    lu.assertEquals(self.world:storageCapacity(), 0)
    lu.assertTrue(self.world:get(5, 5).floor)
    local site = self.world:addSite(SITE_WALL, 5, 5)
    lu.assertNil(site, 'nothing is built on a floor')
end

function TestArcadeWorker:testBuilderStaysOnTheCampSideOfAWall()
    -- a stone pocket with a one tile mouth: the wall goes in the mouth and
    -- the builder must stand outside, else it is shut in
    local world = World.fromGrid({
        '..........',
        '.###......',
        '.#.#.BB...',
        '.#.#.BB...',
        '.#.#......',
        '..........',
    }, Rng.new(1))
    world.arcade = true
    world.stock = { logs = 5, gold = 0 }
    local jobs = Jobs.new()
    local abilities = Abilities.new(world, jobs, function() end)
    abilities:select(ABILITY_WALL)
    lu.assertTrue(abilities:use(3, 5))
    local site = world:get(3, 5).site
    local spot = world:siteApproachTile(site)
    lu.assertEquals(spot, { x = 3, y = 6 }, 'stand on the open side, not in the pocket')
    local twins = Worker.new(world, jobs, Scoring.new(2), Rng.new(1), { x = 6, y = 4, role = ROLE_BUILDER, sheet = 'twins' })
    self.jobs, self.world = jobs, world
    self:run({ twins }, 20)
    lu.assertEquals(world:get(3, 5).type, TILE_WALL)
    local t = twins:tile()
    lu.assertTrue(world:isReachable(t.x, t.y), 'the builder can still walk home')
end

os.exit(lu.LuaUnit.run())
