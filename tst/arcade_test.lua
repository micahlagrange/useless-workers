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
function TestArcadeLevels:testWellFormedLevels()
    lu.assertEquals(Campaign.count('arcade'), 7)
    lu.assertEquals(Campaign.count(), 5) -- survival untouched
    local seen = {}
    for i = 1, Campaign.count('arcade') do
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
    for _, species in ipairs({ 'pupper', 'woofoof', 'twins', 'cwab', 'blue', 'ribbit' }) do
        lu.assertTrue(seen[species], species .. ' never shows up')
    end
    lu.assertEquals(#Campaign.arcade[Campaign.count('arcade')].morphis, 6) -- the last level has everyone
    -- each level asks for everything the one before did, and then some
    local last = 0
    for i = 1, Campaign.count('arcade') do
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
-- The stuck check: a river with no bridge means nobody can reach food;
-- once the bridge is built somebody can. On a picky level a reachable bin
-- and a reachable bush count as food on its way, before anything is stored.
function TestArcadeLevels:testCanReachFoodFollowsTheBridge()
    local run = Campaign.load(2, Rng.new(2), 'arcade', 2)
    local jobs = Jobs.new()
    for _, node in ipairs(run.world.nodes) do if node.ready then jobs:postNode(node) end end
    local scoring = Scoring.new(2)
    local workers = spawn(run, jobs, scoring)
    for _, w in ipairs(workers) do
        lu.assertFalse(w:canReachFood(), w.name .. ' should not reach food across the river')
    end
    local abilities = Abilities.new(run.world, jobs, function() end)
    lu.assertTrue((Campaign.apply(run.def.clever, abilities)))
    local clock = 0
    while clock < 60 and #run.world.sites > 0 do
        clock = clock + DT
        jobs:update(DT)
        run.world:update(DT, function(n) jobs:postNode(n) end)
        for _, w in ipairs(workers) do w:update(DT, clock) end
    end
    lu.assertEquals(#run.world.sites, 0, 'bridge should be built')
    local reach = 0
    for _, w in ipairs(workers) do if w:canReachFood() then reach = reach + 1 end end
    lu.assertTrue(reach > 0, 'after the bridge somebody can reach food')
end

function TestArcadeLevels:testPickyLevelCountsAnEmptyBinAsFoodOnItsWay()
    local run = Campaign.load(4, Rng.new(4), 'arcade', 2) -- Picky
    local jobs = Jobs.new()
    local scoring = Scoring.new(2)
    local workers = spawn(run, jobs, scoring)
    lu.assertTrue(run.world.arcadeNeeds.bins)
    lu.assertFalse(workers[1]:canReachFood(), 'no bin yet, nothing on its way')
    local spot = run.world:spawnTiles(2)[1]
    run.world:markStorage(spot.x, spot.y, STORAGE_BIN_CAPACITY)
    lu.assertTrue(workers[1]:canReachFood(), 'a reachable bin and a ripe bush mean a meal is coming')
end

-- A level's solutions are optional test data. Where a level has them, the
-- obvious build feeds everyone on the hard budget within the easy target
-- (two stars), and the clever one within the clever target (three).
local function hasBuild(def, name)
    return def[name] ~= nil and next(def[name]) ~= nil
end

function TestArcadeLevels:testObviousSolutionsMeetTheEasyTargetOnHard()
    for i = 1, Campaign.count('arcade') do
        local def = Campaign.arcade[i]
        if hasBuild(def, 'obvious') or i == 1 then
            local allAte, spent, clock = play(i, 'obvious', nil, 3)
            print(string.format('  arcade %d obvious: spent %d (easy target %d), fed in %ds', i, spent, def.targets.easy, math.floor(clock)))
            lu.assertTrue(allAte, 'arcade ' .. i .. ': not everyone ate on the obvious solution')
            lu.assertTrue(spent <= def.points.hard, 'arcade ' .. i .. ' obvious solution does not fit the hard budget')
            lu.assertTrue(spent <= def.targets.easy, 'arcade ' .. i .. ' obvious solution misses the easy target')
            lu.assertEquals(Campaign.stars(spent, def) >= 2, true)
        end
    end
end

function TestArcadeLevels:testCleverSolutionsMeetTheCleverTarget()
    for i = 1, Campaign.count('arcade') do
        local def = Campaign.arcade[i]
        if hasBuild(def, 'clever') or i == 1 then
            local allAte, spent, clock = play(i, 'clever')
            print(string.format('  arcade %d clever:  spent %d (clever target %d), fed in %ds', i, spent, def.targets.clever, math.floor(clock)))
            lu.assertTrue(allAte, 'arcade ' .. i .. ': not everyone ate on the clever solution')
            lu.assertTrue(spent <= def.targets.clever, 'arcade ' .. i .. ' clever solution misses the clever target')
            lu.assertEquals(Campaign.stars(spent, def), 3)
        end
    end
end

function TestArcadeLevels:testStarsAndPerfect()
    local def = { targets = { easy = 5, clever = 2 } }
    lu.assertEquals(Campaign.stars(0, def), 3)
    lu.assertEquals(Campaign.stars(2, def), 3)
    lu.assertEquals(Campaign.stars(3, def), 2)
    lu.assertEquals(Campaign.stars(5, def), 2)
    lu.assertEquals(Campaign.stars(6, def), 1)
    -- level 1 asks for nothing: watching it is a perfect clear
    lu.assertEquals(Campaign.arcade[1].targets.clever, 0)
end

function TestArcadeLevels:testNobodyEatsBeforeTheNeedsAreMet()
    -- level 2 with no bridge: the food is out of reach, nobody eats, nobody leaves
    local allAte, _, _, workers = play(2, nil, 40)
    lu.assertFalse(allAte)
    for _, w in ipairs(workers) do
        lu.assertTrue(w.alive)
        lu.assertEquals(w.hunger, HUNGER_MAX)
    end
    -- level 4 (Picky) with no bin: food within reach, but they are picky
    allAte, _, _, workers = play(4, nil, 40)
    lu.assertFalse(allAte)
    lu.assertEquals(Campaign.ateCount(workers), 0)
end

function TestArcadeLevels:testGoalChecklistTicksLive()
    local run = Campaign.load(7, Rng.new(7), 'arcade') -- Inside
    local workers = spawn(run, Jobs.new(), Scoring.new(2))
    local goals = Campaign.goals(run, workers)
    lu.assertEquals(#goals, 5)
    for _, g in ipairs(goals) do lu.assertFalse(g.done, g.label) end
    local world = run.world
    world:markBin(6, 4)
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
    lu.assertTrue(goals[4].done)   -- the bin at 6,4 is inside
    lu.assertFalse(goals[5].done)
    workers[1].ate = true
    goals = Campaign.goals(run, workers)
    lu.assertStrContains(goals[5].label, '1/6')
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
    w:markBin(4, 4) -- both its tiles inside
    lu.assertTrue(w:binsInside())
    w:markBin(7, 2)
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
    w:markBin(4, 4)
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

function TestArcadeWorker:testAMorphiStepsOffATileThatTurnsIntoAWall()
    local pupper = self.make('pupper', 6, 5)
    pupper.ate = true
    self.world:setType(6, 5, TILE_WALL)
    self:run({ pupper }, 1)
    local t = pupper:tile()
    lu.assertTrue(self.world:isPassable(t.x, t.y), 'stepped off the wall')
    lu.assertTrue(self.world:isReachable(t.x, t.y))
    lu.assertTrue(t.x ~= 6 or t.y ~= 5)
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
