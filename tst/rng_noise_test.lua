local lu = require('libs.luaunit')
local Rng = require('src.rng')
local Noise = require('src.noise')

TestRng = {}
function TestRng:testDeterministic()
    local a, b = Rng.new(42), Rng.new(42)
    for _ = 1, 20 do lu.assertEquals(a:random(), b:random()) end
end
function TestRng:testRange()
    local r = Rng.new(7)
    for _ = 1, 500 do
        local v = r:random()
        lu.assertTrue(v >= 0 and v < 1)
        local i = r:int(3, 5)
        lu.assertTrue(i >= 3 and i <= 5)
    end
end
function TestRng:testSeedToNumber()
    lu.assertEquals(Rng.seedToNumber('987'), 987)
    lu.assertEquals(Rng.seedToNumber('bananas'), Rng.seedToNumber('bananas'))
    lu.assertNotEquals(Rng.seedToNumber('bananas'), Rng.seedToNumber('bananaz'))
end
function TestRng:testShuffleKeepsElements()
    local r = Rng.new(3)
    local list = r:shuffle({ 1, 2, 3, 4, 5 })
    table.sort(list)
    lu.assertEquals(list, { 1, 2, 3, 4, 5 })
end

TestNoise = {}
function TestNoise:testRangeAndDeterminism()
    local n1, n2 = Noise.new(987), Noise.new(987)
    local n3 = Noise.new(988)
    local differs = false
    for x = 1, 40 do
        for y = 1, 40 do
            local v = n1:value(x, y)
            lu.assertTrue(v >= 0 and v <= 1)
            lu.assertEquals(v, n2:value(x, y))
            if math.abs(v - n3:value(x, y)) > 0.01 then differs = true end
        end
    end
    lu.assertTrue(differs)
end
function TestNoise:testSmooth()
    local n = Noise.new(5)
    for x = 1, 30 do
        lu.assertTrue(math.abs(n:value(x, 10) - n:value(x + 1, 10)) < 0.25)
    end
end

os.exit(lu.LuaUnit.run())
