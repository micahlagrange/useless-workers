local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Routes = require('src.routes')

TestRoutes = {}

local function setup(logs)
    local world = World.generate(987, Rng.new(987))
    world:spawnAllNodes(NODES_INITIAL)
    world.stock.logs = logs
    return world, Jobs.new()
end

local function unreachable(world, kind)
    for _, n in ipairs(world.nodes) do
        if n.kind == kind and n.ready and not world:nodeReachable(n) then return n end
    end
end

function TestRoutes:testMarksAWayToUnreachableOre()
    local world, jobs = setup(50)
    lu.assertNotNil(unreachable(world, NODE_ORE), 'seed 987 should have ore out of reach')
    local target = Routes.open(world, jobs, NODE_ORE)
    lu.assertNotNil(target)
    lu.assertEquals(target.kind, NODE_ORE)
    lu.assertTrue(#world.selfRouteSites > 0)
    for _, site in ipairs(world.selfRouteSites) do
        lu.assertTrue(site.kind == SITE_MINE or site.kind == SITE_BRIDGE)
        local t = world:get(site.x, site.y)
        lu.assertTrue(t.type == TILE_STONE or t.type == TILE_SNOW or t.type == TILE_WATER)
    end
    lu.assertTrue(jobs:count() > 0, 'the route is on the job queue')
    lu.assertTrue(Routes.pending(world))
end

function TestRoutes:testOneRouteAtATime()
    local world, jobs = setup(50)
    lu.assertNotNil(Routes.open(world, jobs, NODE_ORE))
    lu.assertNil(Routes.open(world, jobs, NODE_TREE))
    for _, site in ipairs(world.selfRouteSites) do world:removeSite(site) end
    lu.assertFalse(Routes.pending(world))
end

function TestRoutes:testBridgesArePaidOrSkipped()
    local world, jobs = setup(0)
    local target = Routes.open(world, jobs, nil)
    lu.assertEquals(world.stock.logs, 0)
    if target then
        for _, site in ipairs(world.selfRouteSites) do lu.assertEquals(site.kind, SITE_MINE) end
    end
    local rich = setup(50)
    local before = rich.stock.logs
    Routes.open(rich, Jobs.new(), nil)
    local bridges = 0
    for _, site in ipairs(rich.selfRouteSites or {}) do if site.kind == SITE_BRIDGE then bridges = bridges + 1 end end
    lu.assertEquals(before - rich.stock.logs, bridges * COSTS.bridge.logs)
end

function TestRoutes:testCapOnRouteLength()
    local world, jobs = setup(50)
    lu.assertNil(Routes.open(world, jobs, NODE_ORE, 0))
    lu.assertNil(world.selfRouteSites)
end

os.exit(lu.LuaUnit.run())
