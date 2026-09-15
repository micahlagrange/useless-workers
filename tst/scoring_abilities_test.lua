local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Abilities = require('src.abilities')
local Highscore = require('src.highscore')

TestScoring = {}
function TestScoring:testGrades()
    lu.assertEquals(Scoring.grade(16, 0, 0), 'S')
    lu.assertEquals(Scoring.grade(12, 1, 0), 'A')
    lu.assertEquals(Scoring.grade(10, 1, 1), 'B')
    lu.assertEquals(Scoring.grade(5, 3, 0), 'C')
    lu.assertEquals(Scoring.grade(2, 3, 1), 'F')
end
function TestScoring:testQuarterCloseAndHires()
    local s = Scoring.new(2)
    for _ = 1, 10 do s:addDelivery(CARGO_FOOD) end
    s:addDelivery(CARGO_LOGS)
    s:addDelivery(CARGO_GOLD)
    s:addComplaint()
    s:sampleFed(50); s:sampleFed(70)
    local r = s:closeQuarter(4)
    lu.assertEquals(r.output, 12)
    lu.assertEquals(r.food, 10)
    lu.assertEquals(r.logs, 1)
    lu.assertEquals(r.gold, 1)
    lu.assertEquals(s:lifetimeValue(), 10 + 2 + 3)
    lu.assertEquals(r.fedPct, 60)
    lu.assertEquals(r.complaints, 1)
    lu.assertEquals(r.grade, 'A')
    lu.assertEquals(r.hires, 2)
    lu.assertEquals(s.budget, BUDGET_START + BUDGET_PER_QUARTER + 12)
    lu.assertEquals(s.quarter, 2)
    lu.assertEquals(s.output, 0)
    -- nobody quit and no output still hires one
    lu.assertEquals(s:hiresFor(0, 0, 4), 1)
    lu.assertEquals(s:hiresFor(0, 1, 4), 0)
    lu.assertEquals(s:hiresFor(100, 0, 11), 1)
    lu.assertEquals(s:hiresFor(100, 0, 12), 0)
end
function TestScoring:testYearAndFinalScore()
    local s = Scoring.new(3)
    for _ = 1, 4 do
        for _ = 1, 5 do s:addDelivery(CARGO_GOLD) end
        s:closeQuarter(3)
    end
    lu.assertTrue(s:yearComplete())
    s:addQuit()
    lu.assertEquals(s:finalScore(), math.floor((20 * 3 - 3) * 1.5))
    s:startEndless()
    lu.assertFalse(s:yearComplete())
    local drain = s.drain
    s:closeQuarter(3)
    lu.assertTrue(s.drain > drain)
end
function TestScoring:testTimerAndFedSampling()
    local s = Scoring.new(1)
    local ended = false
    for _ = 1, 100 do if s:update(1, 80) then ended = true end end
    lu.assertTrue(ended)
    lu.assertTrue(s.fedCount >= 89)
end

TestAbilities = {}
function TestAbilities:setUp()
    self.world = World.fromGrid({
        '..###..........',
        '..#b#..........',
        '..###..........',
        'BB.~~..........',
        'BB.~~..........',
    }, Rng.new(1))
    self.scoring = Scoring.new(2)
    self.jobs = Jobs.new()
    self.effects = {}
    self.abilities = Abilities.new(self.world, self.scoring, self.jobs, function(name) self.effects[#self.effects + 1] = name end)
end
function TestAbilities:testDigCostsBudget()
    self.abilities:select(ABILITY_DIG)
    lu.assertFalse((self.abilities:use(1, 1)))   -- grass
    lu.assertTrue((self.abilities:use(3, 2)))
    lu.assertEquals(self.scoring.budget, BUDGET_START - 1)
    lu.assertEquals(self.effects[1], 'dig')
    self.scoring.budget = 0
    local ok, why = self.abilities:use(3, 3)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'budget')
end
function TestAbilities:testExplodeOpensPocket()
    self.abilities:select(ABILITY_EXPLODE)
    lu.assertFalse(self.world:isReachable(4, 2))
    lu.assertTrue((self.abilities:use(4, 2)))
    lu.assertEquals(self.scoring.budget, BUDGET_START - 4)
    lu.assertTrue(self.world:isReachable(4, 2))
    lu.assertEquals(self.world:get(4, 2).type, TILE_GRASS) -- the bush tile itself was grass
end
function TestAbilities:testBridgeAllOrNothing()
    self.abilities:select(ABILITY_LINE)
    local ok, why = self.abilities:useLine(1, 1, 3, 1)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'water')
    self.scoring.budget = 1
    ok = self.abilities:useLine(3, 4, 6, 4)
    lu.assertFalse(ok)
    lu.assertEquals(self.world:get(4, 4).type, TILE_WATER)
    self.scoring.budget = 2
    lu.assertTrue((self.abilities:useLine(3, 4, 6, 4)))
    lu.assertEquals(self.scoring.budget, 0)
    lu.assertEquals(self.world:get(4, 4).type, TILE_BRIDGE)
    lu.assertEquals(self.world:get(5, 4).type, TILE_BRIDGE)
    lu.assertTrue(self.world:isReachable(6, 4))
end
function TestAbilities:testMemoPrioritizes()
    local bush = self.world.nodes[1]
    local other = self.world:addNode(NODE_BUSH, 15, 1); other.ready = true -- outside the memo radius
    self.jobs:postNode(other)
    self.jobs:postNode(bush)
    self.abilities:select(ABILITY_MEMO)
    lu.assertTrue((self.abilities:use(4, 2)))
    lu.assertEquals(self.jobs:take('forage').node, bush)
    lu.assertEquals(self.scoring.budget, BUDGET_START - 2)
end

TestHighscore = {}
function TestHighscore:testMemoryFallback()
    Highscore.resetMemory()
    lu.assertEquals(Highscore.load(2), 0)
    lu.assertTrue(Highscore.save(2, 40))
    lu.assertFalse(Highscore.save(2, 30))
    lu.assertEquals(Highscore.load(2), 40)
end

os.exit(lu.LuaUnit.run())
