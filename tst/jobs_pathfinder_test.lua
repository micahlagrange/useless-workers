local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Pathfinder = require('src.pathfinder')

TestJobs = {}
local function bush(x, y, ready) return { kind = NODE_BUSH, x = x, y = y, ready = ready ~= false } end
local function tree(x, y) return { kind = NODE_TREE, x = x, y = y, ready = true } end
function TestJobs:testFifoAndDuplicates()
    local jobs = Jobs.new()
    local t1, t2 = bush(1, 1), bush(2, 2)
    lu.assertTrue(jobs:postNode(t1))
    lu.assertTrue(jobs:postNode(t2))
    lu.assertFalse(jobs:postNode(t1))
    lu.assertEquals(jobs:count(), 2)
    local j = jobs:take('forage')
    lu.assertEquals(j.node, t1)
    lu.assertEquals(j.type, 'forage')
    lu.assertEquals(jobs:count(), 1)
end
function TestJobs:testTakeByTypeSkipsStaleAndPredicate()
    local jobs = Jobs.new()
    local stale, good, other, wood = bush(1, 1, false), bush(2, 2), bush(3, 3), tree(4, 4)
    jobs:postNode(stale)
    jobs:postNode(good)
    jobs:postNode(wood)
    jobs:postNode(other)
    lu.assertNil(jobs:take('mine'))
    local j = jobs:take('forage', function(job) return job.x == 3 end)
    lu.assertEquals(j.node, other)
    lu.assertEquals(jobs:count(), 2) -- stale dropped, good and the tree remain
    lu.assertEquals(jobs:count('chop'), 1)
    lu.assertEquals(jobs:take('chop').node, wood)
    lu.assertEquals(jobs:take('forage').node, good)
    lu.assertNil(jobs:take('forage'))
end
function TestJobs:testTakeNearestClaimsAtomically()
    local jobs = Jobs.new()
    local far, near, mid, wood = bush(1, 1), bush(9, 9), bush(5, 5), tree(9, 8)
    jobs:postNode(far)
    jobs:postNode(near)
    jobs:postNode(mid)
    jobs:postNode(wood)
    -- nearest of the types I can do, not the oldest
    local j = jobs:takeNearest({ 'forage' }, 9, 9, nil, nil)
    lu.assertEquals(j.node, near)
    lu.assertEquals(jobs:count('forage'), 2)
    -- across types: the tree next door beats the bush further off
    j = jobs:takeNearest({ 'forage', 'chop' }, 9, 9, nil, nil)
    lu.assertEquals(j.node, wood)
    -- a claim that refuses moves on to the next nearest; a refused job stays queued
    local refused = {}
    j = jobs:takeNearest({ 'forage' }, 5, 5, nil, function(job)
        if job.node == mid then refused[#refused + 1] = job; return false end
        job.node.claimedBy = 'me'
        return true
    end)
    lu.assertEquals(j.node, far)
    lu.assertEquals(far.claimedBy, 'me')
    lu.assertEquals(#refused, 1)
    lu.assertEquals(jobs:count(), 1)
    lu.assertTrue(jobs:hasJobFor(mid))
    -- the try limit bounds path attempts
    lu.assertNil(jobs:takeNearest({ 'forage' }, 5, 5, nil, function() return false end, 1))
    lu.assertEquals(jobs:count(), 1)
end
function TestJobs:testPrioritize()
    local jobs = Jobs.new()
    local a, b = bush(1, 1), bush(2, 2)
    jobs:postNode(a)
    jobs:postNode(b)
    jobs:postNode(b, true)
    lu.assertEquals(jobs:take('forage').node, b)
end

TestPathfinder = {}
function TestPathfinder:testPathAroundWall()
    local world = World.fromGrid({
        '.....',
        '.###.',
        '.#B..',
        '.#B..',
        '.....',
    }, Rng.new(1))
    local path = Pathfinder.find(world, 1, 1, 4, 3)
    lu.assertNotNil(path)
    lu.assertEquals(path[1], { x = 1, y = 1 })
    lu.assertEquals(path[#path], { x = 4, y = 3 })
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        lu.assertEquals(math.abs(a.x - b.x) + math.abs(a.y - b.y), 1)
        lu.assertTrue(world:isPassable(b.x, b.y))
    end
end
function TestPathfinder:testNoPath()
    local world = World.fromGrid({
        '.#.',
        '.#.',
        'B#.',
    }, Rng.new(1))
    lu.assertNil(Pathfinder.find(world, 1, 1, 3, 1))
    lu.assertNil(Pathfinder.find(world, 1, 1, 2, 1))
    lu.assertEquals(#Pathfinder.find(world, 1, 1, 1, 1), 1)
end
function TestPathfinder:testBigMapPerformance()
    local world = World.generate(987, Rng.new(987))
    local reach = world:reachableFromBreakroom()
    local targets = {}
    for x = 1, world.w do for y = 1, world.h do
        if reach[x][y] and #targets < 40 and (x * 7 + y * 3) % 11 == 0 then targets[#targets + 1] = { x = x, y = y } end
    end end
    local start = os.clock()
    local br = world.breakroom.tiles[1]
    for _, t in ipairs(targets) do
        lu.assertNotNil(Pathfinder.find(world, br.x, br.y, t.x, t.y))
    end
    local elapsed = os.clock() - start
    lu.assertTrue(elapsed < 5, 'pathfinding too slow: ' .. elapsed)
end

os.exit(lu.LuaUnit.run())
