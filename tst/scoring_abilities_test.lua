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
    self.world.stock = { logs = 4, gold = 2 }
    self.jobs = Jobs.new()
    self.effects = {}
    self.abilities = Abilities.new(self.world, self.jobs, function(name) self.effects[#self.effects + 1] = name end)
end
function TestAbilities:testMineDesignationPostsJobsAndIsFree()
    self.abilities:select(ABILITY_MINE)
    lu.assertFalse((self.abilities:use(1, 1)))              -- grass
    lu.assertTrue((self.abilities:designateMine(3, 1, 5, 3)))  -- the ring around the bush
    lu.assertEquals(#self.world:sitesOfKind(SITE_MINE), 8)
    lu.assertEquals(self.jobs:count('mine'), 1)                 -- one job for the whole drag
    lu.assertEquals(#self.world.areas, 1)
    lu.assertEquals(#self.world.areas[1].sites, 8)
    lu.assertEquals(self.world.stock.logs, 4)
    lu.assertEquals(self.effects[1], 'mine')
    -- dragging from a marked tile clears marks
    lu.assertTrue((self.abilities:designateMine(3, 1, 3, 3)))
    lu.assertEquals(#self.world:sitesOfKind(SITE_MINE), 5)
    lu.assertEquals(#self.world.areas[1].sites, 5)
    lu.assertNil(self.world:get(3, 2).site)
    -- clearing everything removes the area and its job
    lu.assertTrue((self.abilities:designateMine(4, 1, 5, 3)))
    lu.assertEquals(#self.world.areas, 0)
    lu.assertNil(self.jobs:take('mine'))
end
function TestAbilities:testFloorSpotIsFreeAndBinCostsALog()
    self.abilities:select(ABILITY_STORAGE)
    lu.assertTrue((self.abilities:use(3, 4)))
    lu.assertEquals(self.world.stock.logs, 4)                -- floor spots are free
    lu.assertEquals(self.jobs:count('build'), 1)
    lu.assertEquals(self.world:get(3, 4).site.kind, SITE_STORAGE)
    lu.assertTrue((self.abilities:use(3, 4)))                -- same tool again cancels
    lu.assertNil(self.world:get(3, 4).site)
    lu.assertTrue((self.abilities:use(3, 4)))
    local ok, why
    self.abilities:select(ABILITY_BIN)
    lu.assertTrue((self.abilities:use(6, 1)))
    lu.assertEquals(self.world.stock.logs, 4 - COSTS.bin.logs)
    lu.assertEquals(self.world:get(6, 1).site.kind, SITE_BIN)
    self.world.stock.logs = 0
    ok, why = self.abilities:use(7, 1)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'logs')
    ok, why = self.abilities:use(1, 4)                       -- break room furniture
    lu.assertFalse(ok)
end
function TestAbilities:testDesignationsCancelAndSwap()
    self.abilities:select(ABILITY_STORAGE)
    lu.assertTrue((self.abilities:use(3, 4)))
    local floor = self.world:get(3, 4).site
    lu.assertEquals(floor.kind, SITE_STORAGE)
    -- the bin tool on a floor mark turns it into a bin mark and charges the log
    self.abilities:select(ABILITY_BIN)
    lu.assertTrue((self.abilities:use(3, 4)))
    local bin = self.world:get(3, 4).site
    lu.assertEquals(bin.kind, SITE_BIN)
    lu.assertTrue(floor.done)
    lu.assertFalse(self.jobs:hasJobForSite(floor))
    lu.assertTrue(self.jobs:hasJobForSite(bin))
    lu.assertEquals(self.world.stock.logs, 3)
    -- the same tool on its own mark cancels it and refunds
    lu.assertTrue((self.abilities:use(3, 4)))
    lu.assertNil(self.world:get(3, 4).site)
    lu.assertFalse(self.jobs:hasJobForSite(bin))
    lu.assertEquals(self.world.stock.logs, 4)
    lu.assertEquals(#self.world.sites, 0)
    -- a bridge mark is cancelled by a click (no drag) with the bridge tool
    self.abilities:select(ABILITY_BRIDGE)
    lu.assertTrue((self.abilities:useLine(4, 4, 5, 4)))
    lu.assertEquals(self.world.stock.logs, 2)
    lu.assertTrue((self.abilities:useLine(4, 4, 4, 4)))
    lu.assertNil(self.world:get(4, 4).site)
    lu.assertNotNil(self.world:get(5, 4).site)
    lu.assertEquals(self.world.stock.logs, 3)
    -- no refund once someone is building it
    self.abilities:select(ABILITY_BED)
    lu.assertTrue((self.abilities:use(3, 4)))
    self.world:get(3, 4).site.working = true
    lu.assertEquals(self.world.stock.logs, 1)
    self.abilities:select(ABILITY_BIN)
    local ok, why = self.abilities:use(3, 4)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'already building')
    self.abilities:select(ABILITY_BED)
    lu.assertTrue((self.abilities:use(3, 4)))
    lu.assertEquals(self.world.stock.logs, 1)
end
function TestAbilities:testBedSiteCostsLogsAndBecomesABed()
    self.abilities:select(ABILITY_BED)
    lu.assertTrue((self.abilities:use(3, 4)))
    lu.assertEquals(self.world.stock.logs, 4 - COSTS.bed.logs)
    lu.assertEquals(self.jobs:count('woodwork'), 1)                -- lumberjack work, not a generic build
    local site = self.world:get(3, 4).site
    lu.assertEquals(site.kind, SITE_BED)
    self.world:completeSite(site)
    lu.assertTrue(self.world:get(3, 4).bed)
    lu.assertEquals(#self.world.beds, 1)
    local ok = self.abilities:use(3, 4)                     -- can't put a bed on a bed
    lu.assertFalse(ok)
end
function TestAbilities:testBridgeSitesAllOrNothing()
    self.abilities:select(ABILITY_BRIDGE)
    local ok, why = self.abilities:useLine(1, 1, 3, 1)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'water')
    self.world.stock.logs = 1
    ok = self.abilities:useLine(3, 4, 6, 4)
    lu.assertFalse(ok)
    lu.assertNil(self.world:get(4, 4).site)
    self.world.stock.logs = 2
    lu.assertTrue((self.abilities:useLine(3, 4, 6, 4)))
    lu.assertEquals(self.world.stock.logs, 0)
    lu.assertEquals(self.world:get(4, 4).site.kind, SITE_BRIDGE)
    lu.assertEquals(self.world:get(5, 4).site.kind, SITE_BRIDGE)
    lu.assertEquals(self.jobs:count('build'), 2)
    -- completing the sites lays the bridge
    self.world:completeSite(self.world:get(4, 4).site)
    self.world:completeSite(self.world:get(5, 4).site)
    lu.assertEquals(self.world:get(5, 4).type, TILE_BRIDGE)
    lu.assertTrue(self.world:isReachable(6, 4))
    lu.assertEquals(#self.world.sites, 0)
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
