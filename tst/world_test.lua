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

function TestWorldGen:testTreesLandOnGrassWithSomeEnclosed()
    local world = World.generate(987, Rng.new(987))
    local planted = world:spawnTrees(TREES_INITIAL)
    lu.assertEquals(#planted, TREES_INITIAL)
    local reachable, enclosed = 0, 0
    for _, tree in ipairs(planted) do
        lu.assertEquals(world:get(tree.x, tree.y).type, TILE_GRASS)
        lu.assertEquals(world:get(tree.x, tree.y).tree, tree)
        if world:isReachable(tree.x, tree.y) then reachable = reachable + 1 else enclosed = enclosed + 1 end
    end
    lu.assertTrue(reachable >= 6, 'reachable trees: ' .. reachable)
    lu.assertTrue(enclosed >= 2, 'enclosed trees: ' .. enclosed)
    -- cap
    world:spawnTrees(100)
    lu.assertEquals(#world.trees, MAX_TREES)
end

function TestWorldGen:testTreesRipenAndPost()
    local world = World.generate(3, Rng.new(3))
    world:spawnTrees(5)
    local ripened = {}
    for _ = 1, 120 do world:update(0.1, function(t) ripened[#ripened + 1] = t end) end
    lu.assertEquals(#ripened, 5)
    lu.assertEquals(world:ripeTreeCount(), 5)
    world:harvest(ripened[1])
    lu.assertFalse(ripened[1].ripe)
    lu.assertEquals(ripened[1].timer, TREE_RIPEN_SECONDS)
end

TestWorldTools = {}
local grid = {
    '..........',
    '..#####...',
    '..#...#...',
    '..#.T.#...',
    '..#####...',
    '.BB.......',
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
    lu.assertEquals(#self.world.trees, 1)
    lu.assertTrue(self.world.trees[1].ripe)
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
