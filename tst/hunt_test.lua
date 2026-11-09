local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')
local Hunt = require('src.hunt')

local DT = 1 / 30

local party = {
    { name = 'Pupper', sheet = 'pupper', species = 'pupper', role = ROLE_HUNTER },
    { name = 'Woofoof', sheet = 'woofoof', species = 'woofoof', role = ROLE_HUNTER },
    { name = 'Twins', sheet = 'twins', species = 'twins', role = ROLE_BUILDER },
}

local function hunt(n)
    local run = assert(Hunt.load(n, Rng.new(n), party))
    local world = run.world
    local jobs = Jobs.new()
    for _, node in ipairs(world.nodes) do
        if node.ready then jobs:postNode(node) end
    end
    local scoring = Scoring.new(2)
    local workers = {}
    for i, spec in ipairs(run.specs) do
        workers[#workers + 1] = Worker.new(world, jobs, scoring, Rng.new(i), {
            x = spec.x, y = spec.y, role = spec.role, sheet = spec.sheet, name = spec.name, diet = spec.diet,
        })
    end
    local clock = 0
    while clock < 300 and not Hunt.won(world) do
        clock = clock + DT
        jobs:update(DT)
        world:update(DT, function(nd) jobs:postNode(nd) end)
        for _, w in ipairs(workers) do w:update(DT, clock) end
    end
    return run, world, clock
end

TestHunt = {}

function TestHunt:testGroundsHaveCritters()
    lu.assertTrue(Hunt.count() >= 2)
    for n = 1, Hunt.count() do
        local run = Hunt.load(n, nil, party)
        lu.assertTrue(run.critters > 0, 'ground ' .. n .. ' has no critters')
        lu.assertEquals(Hunt.crittersLeft(run.world), run.critters)
        for _, node in ipairs(run.world.nodes) do
            lu.assertNotEquals(node.kind, NODE_BUSH)
            if node.kind == NODE_CRITTER then lu.assertTrue(run.world:isReachable(node.x, node.y), 'critter out of reach on ground ' .. n) end
        end
        lu.assertEquals(#run.specs, #party)
        for _, s in ipairs(run.specs) do lu.assertEquals(s.role, ROLE_HUNTER) end
    end
end

function TestHunt:testEveryGroundCanBeWon()
    for n = 1, Hunt.count() do
        local _, world, clock = hunt(n)
        lu.assertTrue(Hunt.won(world), 'ground ' .. n .. ' not cleared in ' .. clock .. 's')
    end
end

function TestHunt:testPartyPickHuntersFirst()
    local picked = Hunt.pick(party)
    lu.assertEquals(#picked, 3)
    lu.assertEquals(picked[1].role, ROLE_HUNTER)
    lu.assertEquals(picked[3].name, 'Twins')
    local chosen = Hunt.pick(party, { 'Twins' })
    lu.assertEquals(chosen[1].name, 'Twins')
end

function TestHunt:testMeatHome()
    lu.assertEquals(Hunt.weeksAway(), 1)
    local got = Hunt.meatHome(3, 1, 0)
    lu.assertEquals(got, 3 * HUNT_MEAT_PER_WEEK)
    local big, left = Hunt.meatHome(3, 10, 0)
    lu.assertEquals(big, 3 * HUNT_BASKET_MEAT)
    lu.assertEquals(left, 60 - 12)
    lu.assertEquals(Hunt.meatHome(3, 10, 1), 60)
end

function TestHunt:testSeasonDay()
    lu.assertEquals(Hunt.seasonDay(QUARTER_SECONDS), 1)
    lu.assertEquals(Hunt.seasonDay(QUARTER_SECONDS - DAY_SECONDS * (HUNT_LEAVE_DAY - 1) - 0.1), HUNT_LEAVE_DAY)
    lu.assertEquals(Hunt.seasonDay(-5), DAYS_PER_SEASON)
end

function TestHunt:testDeliverFillsStorage()
    local run = assert(Hunt.load(1, Rng.new(1), party))
    local world = run.world
    local before = world:storedCount(ITEM_FOOD)
    lu.assertEquals(Hunt.deliver(world, 6), 6)
    lu.assertEquals(world:storedCount(ITEM_FOOD), before + 6)
    local room = world:storageCapacity() - world:storedCount(ITEM_FOOD)
    lu.assertEquals(Hunt.deliver(world, room + 5), room)
end

os.exit(lu.LuaUnit.run())
