local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')

TestWorldGen = {}
function TestWorldGen:testCompositionAndBreakroom()
    for _, seed in ipairs({ 987, 1, 12345, Rng.seedToNumber('bananas') }) do
        local world = World.generate(seed, Rng.new(seed))
        local counts = world:countTypes()
        local total = WORLD_W * WORLD_H
        lu.assertTrue((counts.water or 0) / total > 0.08 and (counts.water or 0) / total < 0.16)
        lu.assertTrue((counts.stone or 0) / total > 0.25 and (counts.stone or 0) / total < 0.35)
        lu.assertTrue((counts.grass or 0) / total > 0.45)
        lu.assertNotNil(world.breakroom)
        lu.assertEquals(#world.breakroom.tiles, 4)
        for _, t in ipairs(world.breakroom.tiles) do
            lu.assertEquals(world:get(t.x, t.y).type, TILE_BREAKROOM)
            lu.assertTrue(world:isPassable(t.x, t.y))
        end
        local reach = world:reachableFromBreakroom()
        local n = 0
        for x = 1, world.w do for y = 1, world.h do if reach[x][y] then n = n + 1 end end end
        lu.assertTrue(n > 800, 'break room region too small: ' .. n)
    end
end

function TestWorldGen:testDeterministicForSeed()
    local a = World.generate(987, Rng.new(987))
    local b = World.generate(987, Rng.new(987))
    for x = 1, a.w do for y = 1, a.h do
        lu.assertEquals(a.tiles[x][y].type, b.tiles[x][y].type)
    end end
    lu.assertEquals(a.breakroom.x, b.breakroom.x)
end

function TestWorldGen:testNodesLandInTheRightPlaces()
    local world = World.generate(987, Rng.new(987))
    local planted = world:spawnAllNodes(NODES_INITIAL)
    lu.assertEquals(#planted, NODES_INITIAL.bush + NODES_INITIAL.tree + NODES_INITIAL.ore)
    local reachable, enclosed = {}, {}
    for _, node in ipairs(planted) do
        local t = world:get(node.x, node.y)
        lu.assertEquals(t.node, node)
        if node.kind == NODE_ORE then
            lu.assertEquals(t.type, TILE_STONE)
        else
            lu.assertEquals(t.type, TILE_GRASS)
        end
        if world:nodeReachable(node) then
            reachable[node.kind] = (reachable[node.kind] or 0) + 1
        else
            enclosed[node.kind] = (enclosed[node.kind] or 0) + 1
        end
    end
    for _, kind in ipairs(NODE_KINDS) do
        lu.assertTrue((reachable[kind] or 0) >= 3, kind .. ' reachable: ' .. tostring(reachable[kind]))
        lu.assertTrue((enclosed[kind] or 0) >= 1, kind .. ' enclosed: ' .. tostring(enclosed[kind]))
    end
    -- bushes start unripe, trees and ore are ready at once
    for _, node in ipairs(planted) do
        lu.assertEquals(node.ready, node.kind ~= NODE_BUSH)
    end
    -- cap
    world:spawnNodes(NODE_BUSH, 100)
    lu.assertEquals(#world:nodesOfKind(NODE_BUSH), MAX_NODES_PER_KIND)
end

function TestWorldGen:testBushesRipenTreesRegrowOreDepletes()
    local world = World.generate(3, Rng.new(3))
    world:spawnNodes(NODE_BUSH, 5)
    local ready = {}
    for _ = 1, 120 do world:update(0.1, function(n) ready[#ready + 1] = n end) end
    lu.assertEquals(#ready, 5)
    lu.assertEquals(world:readyNodeCount(NODE_BUSH), 5)
    lu.assertEquals(world:harvestNode(ready[1]), CARGO_FOOD)
    lu.assertFalse(ready[1].ready)
    lu.assertEquals(ready[1].timer, BUSH_RIPEN_SECONDS)
    local tree = world:spawnNodes(NODE_TREE, 1)[1]
    lu.assertTrue(tree.ready)
    lu.assertEquals(world:harvestNode(tree), CARGO_LOGS)
    lu.assertFalse(tree.ready)
    lu.assertEquals(tree.timer, TREE_REGROW_SECONDS)
    local ore = world:spawnNodes(NODE_ORE, 1, 0)[1]
    local ox, oy = ore.x, ore.y
    lu.assertEquals(world:get(ox, oy).type, TILE_STONE)
    lu.assertEquals(world:harvestNode(ore), CARGO_GOLD)
    lu.assertEquals(world:get(ox, oy).type, TILE_DIRT)
    lu.assertNil(world:get(ox, oy).node)
    lu.assertEquals(#world:nodesOfKind(NODE_ORE), 0)
end

TestWorldTools = {}
local grid = {
    '..........',
    '..#####...',
    '..#...#...',
    '..#.b.#...',
    '..#####...',
    '.BB....G..',
    '.BB..~~~..',
    '.....~~~..',
}
function TestWorldTools:setUp()
    self.world = World.fromGrid(grid, Rng.new(1))
end
function TestWorldTools:testGridParsing()
    lu.assertEquals(self.world.w, 10)
    lu.assertEquals(self.world.h, 8)
    lu.assertEquals(self.world:get(3, 2).type, TILE_STONE)
    lu.assertEquals(self.world:get(6, 7).type, TILE_WATER)
    lu.assertEquals(#self.world.breakroom.tiles, 4)
    lu.assertEquals(#self.world.nodes, 2)
    lu.assertEquals(self.world.nodes[1].kind, NODE_BUSH)
    lu.assertTrue(self.world.nodes[1].ready)
    lu.assertEquals(self.world.nodes[2].kind, NODE_ORE)
    lu.assertEquals(self.world:get(8, 6).type, TILE_STONE)
end
function TestWorldTools:testOreIsWorkedFromNextDoor()
    local ore = self.world.nodes[2]
    local spot = self.world:approachTile(ore)
    lu.assertNotNil(spot)
    lu.assertTrue(self.world:isPassable(spot.x, spot.y))
    lu.assertEquals(math.abs(spot.x - ore.x) + math.abs(spot.y - ore.y), 1)
    local bush = self.world.nodes[1]
    lu.assertNil(self.world:approachTile(bush)) -- walled in
    self.world:dig(4, 5)
    lu.assertEquals(self.world:approachTile(bush), { x = 5, y = 4 })
end
function TestWorldTools:testEnclosedTreeUnreachableUntilDug()
    lu.assertFalse(self.world:isReachable(5, 4))
    lu.assertTrue(self.world:isReachable(1, 1))
    local v = self.world.version
    lu.assertFalse(self.world:dig(4, 3)) -- grass, nothing to dig
    lu.assertTrue(self.world:dig(4, 5))  -- wall below the pocket
    lu.assertEquals(self.world:get(4, 5).type, TILE_DIRT)
    lu.assertTrue(self.world.version > v)
    lu.assertTrue(self.world:isReachable(5, 4))
end
function TestWorldTools:testExplode()
    local n = self.world:explode(3, 3)
    lu.assertEquals(n, 4) -- (3,2)(4,2)(3,3)(3,4) are stone, (2,2) is grass
    lu.assertEquals(self.world:get(3, 3).type, TILE_DIRT)
    lu.assertEquals(self.world:get(4, 3).type, TILE_GRASS)
end
function TestWorldTools:testLineAndBridge()
    local tiles = self.world:lineTiles(5, 7, 9, 7)
    lu.assertEquals(#tiles, 5)
    lu.assertEquals(self.world:countType(tiles, TILE_WATER), 3)
    for _, p in ipairs(tiles) do self.world:bridge(p.x, p.y) end
    lu.assertEquals(self.world:get(6, 7).type, TILE_BRIDGE)
    lu.assertTrue(self.world:isPassable(7, 7))
    local vertical = self.world:lineTiles(2, 1, 2, 30)
    lu.assertEquals(#vertical, 8) -- clipped to the map
    lu.assertEquals(vertical[2].y, 2)
end
function TestWorldTools:testSpawnTilesNearBreakroom()
    local spots = self.world:spawnTiles(2)
    lu.assertTrue(#spots >= 4)
    for _, s in ipairs(spots) do lu.assertTrue(self.world:isReachable(s.x, s.y)) end
end

os.exit(lu.LuaUnit.run())
