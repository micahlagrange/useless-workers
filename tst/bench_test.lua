-- The sim bench (tools/bench.lua): its sums and tipping points on made-up
-- runs, and one short real run with each player.
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
require('src.constants')
local Bench = dofile('tools/bench.lua')

-- A run whose seasons all share the same numbers, with per-season changes.
local function fakeRun(strategy, seed, bands, opts)
    opts = opts or {}
    local run = { strategy = strategy, seed = seed, seasonSeconds = 100, seasons = {} }
    for s, band in ipairs(bands) do
        local r = Bench.newSeason(s, band)
        r.popEnd = band
        r.mSec = band * 100
        r.moraleSum = band * 100 * 70
        r.above80 = band * 25
        r.idle = band * 10
        r.work = band * 60
        r.food, r.logs, r.gold = 8, 4, 2
        r.trades = band
        r.stockGold = (opts.gold or 0) * s
        r.storedFood = 5
        r.fedPct = 80
        if band == 0 then r.gone = s == (opts.goneAt or s); r.dead = not r.gone; r.mSec = 0; r.moraleSum = 0; r.food, r.logs, r.gold = 0, 0, 0 end
        run.seasons[s] = r
    end
    return run
end

TestBench = {}

function TestBench:test_summarize_skips_holes()
    local s = Bench.summarize({ 2, nil, 4, 6 })
    lu.assertEquals(s.n, 3)
    lu.assertAlmostEquals(s.mean, 4, 1e-9)
    lu.assertAlmostEquals(s.sd, math.sqrt(8 / 3), 1e-9)
    lu.assertEquals(s.min, 2)
    lu.assertEquals(s.max, 6)
    lu.assertEquals(Bench.summarize({}).n, 0)
end

function TestBench:test_a_year_is_four_seasons_of_shares_and_rates()
    local run = fakeRun('active', 'A', { 5, 5, 5, 6, 7, 7, 7, 7 })
    local y1 = Bench.yearValues(run, 1)
    lu.assertEquals(y1.band, 6)
    lu.assertEquals(y1.alive, 1)
    lu.assertAlmostEquals(y1.morale, 70, 1e-9)
    lu.assertAlmostEquals(y1.above80, 0.25, 1e-9)
    lu.assertAlmostEquals(y1.idle, 0.1, 1e-9)
    lu.assertAlmostEquals(y1.work, 0.6, 1e-9)
    -- goods are per season
    lu.assertEquals(y1.food, 8)
    lu.assertEquals(y1.goods, 14)
    -- one trade per morphi per season (a season is 100 s here)
    lu.assertAlmostEquals(y1.trades, 1, 1e-9)
    lu.assertEquals(y1.fun, 0)
    lu.assertEquals(Bench.yearValues(run, 2).band, 7)
    lu.assertNil(Bench.yearValues(run, 3))
end

function TestBench:test_aggregate_over_seeds()
    local runs = { fakeRun('none', 'A', { 4, 4, 4, 4 }), fakeRun('none', 'B', { 6, 6, 6, 8 }), fakeRun('dig', 'A', { 5, 5, 5, 5 }) }
    local agg, order = Bench.aggregate(runs, 1)
    lu.assertEquals(order, { 'none', 'dig' })
    lu.assertEquals(agg.none[1].band.n, 2)
    lu.assertAlmostEquals(agg.none[1].band.mean, 6, 1e-9)
    lu.assertEquals(agg.none[1].band.min, 4)
    lu.assertEquals(agg.none[1].band.max, 8)
    lu.assertAlmostEquals(agg.dig[1].band.mean, 5, 1e-9)
end

function TestBench:test_dead_bands_have_no_morale_and_count_as_lost()
    local run = fakeRun('none', 'A', { 3, 2, 0, 0 }, { goneAt = 3 })
    local y = Bench.yearValues(run, 1)
    lu.assertEquals(y.alive, 0)
    lu.assertEquals(y.band, 0)
    local agg = Bench.aggregate({ run, fakeRun('none', 'B', { 0, 0, 0, 0 }, { goneAt = 1 }) }, 1)
    lu.assertEquals(agg.none[1].alive.mean, 0)
    -- the second band never lived a sampled second: no morale for it
    lu.assertEquals(agg.none[1].morale.n, 1)
end

function TestBench:test_tipping_points()
    local falling = fakeRun('none', 'A', { 5, 6, 7, 7, 6, 5, 4, 3 })
    local t = Bench.tipping(falling)
    lu.assertEquals(t.fall, 5)
    lu.assertEquals(t.peak, 7)
    lu.assertNil(t.goneAt)
    local gone = fakeRun('none', 'B', { 5, 4, 2, 0, 0, 0, 0, 0 }, { goneAt = 4 })
    t = Bench.tipping(gone)
    lu.assertEquals(t.goneAt, 4)
    lu.assertEquals(t.fall, 2)
    lu.assertEquals(t.collapse, 2)
    local steady = fakeRun('active', 'C', { 5, 6, 7, 8, 9, 10, 12, 12, 12, 12, 12, 12 }, { gold = 4 })
    t = Bench.tipping(steady)
    lu.assertNil(t.fall)
    lu.assertEquals(t.capAt, 7)
    -- gold grows 16 a year and ends at 48: piling up from year 2
    lu.assertEquals(t.piles.stockGold, 2)
    lu.assertNil(t.piles.storedFood)
    lu.assertEquals(Bench.seasonLabel(6), 'Y2 Summer')
end

function TestBench:test_runs_survive_the_trip_between_processes()
    local run = fakeRun('beds', 'Z', { 3, 3, 3, 3 })
    run.seasons[1].drain = 0.55
    local back = Bench.deserialize(Bench.serialize(run))
    lu.assertEquals(back, run)
end

function TestBench:test_report_and_csv_have_every_strategy()
    local runs = { fakeRun('active', 'A', { 5, 5, 5, 5 }), fakeRun('none', 'A', { 5, 4, 0, 0 }, { goneAt = 3 }) }
    local text = Bench.report(runs, 1, { label = 'test', seeds = 1, difficulty = 1 })
    lu.assertStrContains(text, '== active ==')
    lu.assertStrContains(text, '== none ==')
    lu.assertStrContains(text, 'died out: A Y1 Autumn')
    local csv = Bench.seasonsCsv(runs)
    local lines = 0
    for _ in csv:gmatch('\n') do lines = lines + 1 end
    lu.assertEquals(lines, 1 + 8)
    lu.assertStrContains(Bench.yearsCsv(runs, 1), 'band_mean')
end

-- The real game, with short seasons so the test stays quick.
function TestBench:test_a_real_run_with_each_player()
    Bench.loadGame({ 'QUARTER_SECONDS = 20', 'DAY_SECONDS = QUARTER_SECONDS / DAYS_PER_SEASON' })
    for _, strategy in ipairs(Bench.Player.STRATEGIES) do
        local run = Bench.runOne('BENCHTEST', strategy, 1, 1)
        lu.assertEquals(#run.seasons, 4)
        lu.assertEquals(run.seasonSeconds, 20)
        lu.assertEquals(run.seasons[1].popStart, DIFFICULTIES[1].workers)
        lu.assertTrue(run.seasons[1].mSec > 0)
        if strategy == 'active' then lu.assertTrue(#Bench.H.game().world:storageTiles() + #Bench.H.game().world.sites > 0) end
        if strategy == 'none' then lu.assertEquals(#Bench.H.game().world.sites, 0) end
    end
    -- same seed, same run
    local a = Bench.serialize(Bench.runOne('BENCHTEST', 'dig', 1, 1))
    local b = Bench.serialize(Bench.runOne('BENCHTEST', 'dig', 1, 1))
    lu.assertEquals(a, b)
end

os.exit(lu.LuaUnit.run())
