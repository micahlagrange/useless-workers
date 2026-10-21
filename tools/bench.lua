-- The simulation bench: free play headless with the real game code, many
-- seeds, several years, four players (tools/sim_player.lua), and a short
-- report of what each player's band does year by year. tools/bench.py runs
-- it (one process per seed and player) and writes the report and CSVs; read
-- that file's header for how. This file has two halves:
--
--   Bench.runOne(seed, strategy, years, difficulty)  plays one run and
--       returns a row per season (needs the game: Bench.loadGame first)
--   Bench.yearValues / aggregate / tipping / report / csv  are plain
--       functions over those rows (tst/bench_test.lua tests them)
--
-- Lua 5.1 compatible, like the game.
require('src.constants')
local Bench = {}

-- One simulation step. The game runs at the screen rate (1/60 s at 60 fps).
-- Checked on 24 seeds x 8 years: 1/30 gives the same yearly means as 1/60
-- within the seed spread; 1/15 (the older sims' step) delivers about 9%
-- fewer goods and loses bands sooner, and 1/10 more so. LuaJIT spends most of
-- its time on decisions and paths, not steps, so 1/30 costs little.
Bench.DT = 1 / 30
Bench.SAMPLE_SECONDS = 1    -- how often each morphi's morale and doing are sampled
Bench.PLAYER_EVERY = 30     -- game seconds between the player's looks at the map

-- Season rows -----------------------------------------------------------

local COUNTED = { 'mSec', 'moraleSum', 'above80', 'below30', 'hungerSum', 'hungry', 'work', 'foodTime', 'rest', 'sulk', 'idle' }

local function newSeason(index, popStart)
    local row = {
        season = index, year = math.floor((index - 1) / 4) + 1, seasonInYear = (index - 1) % 4 + 1,
        popStart = popStart, popEnd = 0, migrants = 0, starved = 0, left = 0, gone = false, dead = false,
        food = 0, logs = 0, gold = 0, beds = 0, trades = 0, fun = 0, complaints = 0, hardships = 0,
        hardHungry = 0, hardBored = 0, hardSlow = 0, hardReach = 0,
        stockLogs = 0, stockGold = 0, storedFood = 0, fedPct = 0, drain = 0, score = 0,
        bushes = 0, ripeBushes = 0, trees = 0, ore = 0,
    }
    for _, k in ipairs(COUNTED) do row[k] = 0 end
    return row
end
Bench.newSeason = newSeason

-- Plays one run and returns { seed, strategy, seasonSeconds, seasons = {row...} }.
-- A band that dies out gets its last season marked gone and the rest dead.
function Bench.runOne(seed, strategy, years, difficulty)
    local H, Player, Stats = Bench.H, Bench.Player, Bench.Stats
    local act = assert(Player.act[strategy], 'unknown strategy ' .. tostring(strategy))
    H.newGame(seed, difficulty or 1)
    H.closeGoal()
    local game = H.game()
    local function band()
        local n = 0
        for _, w in ipairs(game.workers) do if w:isWorking() then n = n + 1 end end
        return n
    end
    local rows = {}
    local cur = newSeason(1, band())
    local counts = {}
    for k, v in pairs(game.stats.counts) do counts[k] = v end
    local seenEvents = #game.stats.events
    local nextSample, nextAct = Bench.SAMPLE_SECONDS, Bench.PLAYER_EVERY
    act(game)

    local function closeRow(row, delivered)
        local sc, w = game.scoring, game.world
        row.food, row.logs, row.gold = delivered.food or 0, delivered.logs or 0, delivered.gold or 0
        local c = game.stats.counts
        row.starved = (c.starved or 0) - (counts.starved or 0)
        row.left = (c.left or 0) - (counts.left or 0)
        row.trades = (c.trade or 0) - (counts.trade or 0)
        row.hardships = (c.hardship or 0) - (counts.hardship or 0)
        for k, v in pairs(c) do counts[k] = v end
        for i = seenEvents + 1, #game.stats.events do
            local e = game.stats.events[i]
            if e.kind == 'hardship' then
                local key = ({ hungry = 'hardHungry', bored = 'hardBored', slow = 'hardSlow' })[e.text] or 'hardReach'
                row[key] = row[key] + 1
            end
        end
        seenEvents = #game.stats.events
        row.beds = #w.beds
        row.stockLogs, row.stockGold = w.stock.logs or 0, w.stock.gold or 0
        row.storedFood = w:storedCount('food')
        row.drain = sc.drain
        row.score = sc:finalScore()
        row.bushes = #w:nodesOfKind(NODE_BUSH)
        row.ripeBushes = w:readyNodeCount(NODE_BUSH)
        row.trees = #w:nodesOfKind(NODE_TREE)
        row.ore = #w:nodesOfKind(NODE_ORE)
        rows[#rows + 1] = row
    end

    while #rows < years * 4 do
        love.update(Bench.DT)
        local st = H.state()
        if st == 'playing' then
            while game.clock >= nextSample do
                nextSample = nextSample + Bench.SAMPLE_SECONDS
                for _, w in ipairs(game.workers) do
                    if w:isWorking() then
                        local m = w.morale or MORALE_MAX
                        cur.mSec = cur.mSec + 1
                        cur.moraleSum = cur.moraleSum + m
                        if m > 80 then cur.above80 = cur.above80 + 1 end
                        if m < 30 then cur.below30 = cur.below30 + 1 end
                        cur.hungerSum = cur.hungerSum + w.hunger
                        if w.hunger < HUNGER_EAT_THRESHOLD then cur.hungry = cur.hungry + 1 end
                        local b = Stats.bucket(w)
                        if b == 'food' then b = 'foodTime' end
                        cur[b] = cur[b] + 1
                    end
                end
            end
            if game.clock >= nextAct then
                nextAct = nextAct + Bench.PLAYER_EVERY
                act(game)
            end
        elseif st == 'report' then
            local rep = game.report
            cur.migrants = rep.hires
            cur.popEnd = band() - rep.hires
            cur.complaints = rep.complaints
            cur.fedPct = rep.fedPct
            closeRow(cur, rep)
            cur = newSeason(#rows + 1, band())
            love.keypressed('return')
        elseif st == 'annual' then
            game.scoring:startEndless()
            H.setState('playing')
        elseif st == 'gameover' then
            cur.gone = true
            cur.complaints = game.scoring.complaints
            cur.fedPct = game.scoring:fedPercent()
            closeRow(cur, game.scoring.delivered)
            while #rows < years * 4 do
                local r = newSeason(#rows + 1, 0)
                r.dead = true
                r.beds, r.stockLogs, r.stockGold, r.storedFood = cur.beds, cur.stockLogs, cur.stockGold, cur.storedFood
                r.score, r.drain = cur.score, cur.drain
                rows[#rows + 1] = r
            end
            break
        else
            error('bench: free play reached an unexpected screen: ' .. tostring(st))
        end
    end
    return { seed = seed, strategy = strategy, seasonSeconds = QUARTER_SECONDS, gameSeconds = game.clock, seasons = rows }
end

-- Loads the game headless once per Lua state. overrides: Lua source run
-- after the constants are in, for trying out other numbers.
function Bench.loadGame(overrides)
    package.path = "./?.lua;./?/init.lua;" .. package.path
    local Stub = dofile('tst/love_stub.lua')
    Stub.install()
    dofile('conf.lua')
    TEST_HOOKS = {}
    dofile('main.lua')
    Bench.H = TEST_HOOKS.main
    Bench.Stats = require('src.stats')
    -- The bench reads only the stats' counts and events, never the day rows,
    -- map snapshots or milestones, and nothing in the game reads them back:
    -- skipping them is faster and changes no outcome.
    Bench.Stats.update = function() end
    Bench.Player = dofile('tools/sim_player.lua')
    Bench.applyOverrides(overrides)
    love.load()
    love.resize(1280, 720)
end

-- Each override is Lua source, such as 'QUARTER_SECONDS = 300'.
function Bench.applyOverrides(overrides)
    for _, src in ipairs(overrides or {}) do
        local chunk = assert((loadstring or load)(src))
        chunk()
    end
end

-- Statistics ------------------------------------------------------------

-- The highest integer key of a list with holes (table.maxn is gone after 5.1).
local function maxn(t)
    local n = 0
    for k in pairs(t) do
        if type(k) == 'number' and k > n then n = k end
    end
    return n
end

-- n, mean, sd (population), min and max of the numbers in a list; nils skipped.
function Bench.summarize(values)
    local n, sum = 0, 0
    local lo, hi = nil, nil
    local last = maxn(values)
    for i = 1, last do
        local v = values[i]
        if v ~= nil then
            n = n + 1
            sum = sum + v
            if lo == nil or v < lo then lo = v end
            if hi == nil or v > hi then hi = v end
        end
    end
    if n == 0 then return { n = 0 } end
    local mean = sum / n
    local sq = 0
    for i = 1, last do
        local v = values[i]
        if v ~= nil then sq = sq + (v - mean) ^ 2 end
    end
    return { n = n, mean = mean, sd = math.sqrt(sq / n), min = lo, max = hi }
end

local function ratio(a, b)
    if not b or b == 0 then return nil end
    return a / b
end

-- One run's numbers for one year (seasons (year-1)*4+1 .. year*4):
-- shares are of morphi-seconds, goods and hardships are per season, trades
-- and fun per morphi per season. Morale and time shares are nil once the
-- band is gone.
Bench.YEAR_METRICS = {
    'alive', 'band', 'lost', 'starved', 'left', 'migrants', 'morale', 'above80', 'below30',
    'idle', 'work', 'foodTime', 'rest', 'sulk', 'hunger', 'hungry',
    'food', 'logs', 'gold', 'goods', 'beds', 'trades', 'fun', 'complaints', 'hardships',
    'hardHungry', 'hardBored', 'hardSlow', 'hardReach',
    'stockLogs', 'stockGold', 'storedFood', 'fedPct', 'drain', 'score',
}

function Bench.yearValues(run, year)
    local first = (year - 1) * 4 + 1
    local sum = {}
    local keys = { 'starved', 'left', 'migrants', 'food', 'logs', 'gold', 'trades', 'fun', 'complaints', 'hardships',
        'hardHungry', 'hardBored', 'hardSlow', 'hardReach' }
    for _, k in ipairs(keys) do sum[k] = 0 end
    for _, k in ipairs(COUNTED) do sum[k] = 0 end
    local fedSum, fedN = 0, 0
    local last
    for s = first, first + 3 do
        local r = run.seasons[s]
        if r then
            last = r
            for _, k in ipairs(keys) do sum[k] = sum[k] + (r[k] or 0) end
            for _, k in ipairs(COUNTED) do sum[k] = sum[k] + (r[k] or 0) end
            if not r.dead then fedSum, fedN = fedSum + (r.fedPct or 0), fedN + 1 end
        end
    end
    if not last then return nil end
    local mSec = sum.mSec
    -- morphi-seasons lived this year, for the per-morphi rates
    local morphiSeasons = mSec / (run.seasonSeconds or QUARTER_SECONDS)
    local v = {
        alive = (last.popEnd > 0) and 1 or 0,
        band = last.popEnd,
        lost = sum.starved + sum.left, starved = sum.starved, left = sum.left, migrants = sum.migrants,
        morale = ratio(sum.moraleSum, mSec), above80 = ratio(sum.above80, mSec), below30 = ratio(sum.below30, mSec),
        idle = ratio(sum.idle, mSec), work = ratio(sum.work, mSec), foodTime = ratio(sum.foodTime, mSec),
        rest = ratio(sum.rest, mSec), sulk = ratio(sum.sulk, mSec),
        hunger = ratio(sum.hungerSum, mSec), hungry = ratio(sum.hungry, mSec),
        food = sum.food / 4, logs = sum.logs / 4, gold = sum.gold / 4, goods = (sum.food + sum.logs + sum.gold) / 4,
        beds = last.beds,
        trades = ratio(sum.trades, morphiSeasons), fun = ratio(sum.fun, morphiSeasons),
        complaints = sum.complaints / 4, hardships = sum.hardships / 4,
        hardHungry = sum.hardHungry / 4, hardBored = sum.hardBored / 4, hardSlow = sum.hardSlow / 4, hardReach = sum.hardReach / 4,
        stockLogs = last.stockLogs, stockGold = last.stockGold, storedFood = last.storedFood,
        fedPct = fedN > 0 and fedSum / fedN or nil,
        drain = last.drain, score = last.score,
    }
    return v
end

-- agg[strategy][year][metric] = summary over the seeds
function Bench.aggregate(runs, years)
    local agg, order = {}, {}
    for _, run in ipairs(runs) do
        if not agg[run.strategy] then agg[run.strategy] = {}; order[#order + 1] = run.strategy end
    end
    for _, strategy in ipairs(order) do
        for y = 1, years do
            local lists = {}
            for _, k in ipairs(Bench.YEAR_METRICS) do lists[k] = {} end
            local i = 0
            for _, run in ipairs(runs) do
                if run.strategy == strategy then
                    i = i + 1
                    local v = Bench.yearValues(run, y)
                    for _, k in ipairs(Bench.YEAR_METRICS) do lists[k][i] = v and v[k] end
                end
            end
            local row = {}
            for _, k in ipairs(Bench.YEAR_METRICS) do row[k] = Bench.summarize(lists[k]) end
            agg[strategy][y] = row
        end
    end
    return agg, order
end

-- Tipping points ----------------------------------------------------------

-- 'Y2 Summer' for season 6.
function Bench.seasonLabel(s)
    return 'Y' .. (math.floor((s - 1) / 4) + 1) .. ' ' .. SEASON_NAMES[(s - 1) % 4 + 1]
end

-- Where one run tips:
--   fall      the season from which the band never again reaches its peak,
--             when it ends at least two below the peak (or dies out)
--   goneAt    the season the band died out
--   collapse  the year after the best year for goods, when the last year
--             brings in less than half of the best
--   capAt     the first season the band ends at MAX_WORKERS
--   piles     for stored food, logs and gold: the first year whose
--             year-end stock is PILE_PER_YEAR or more above the year before,
--             two years running, reaching PILE_MIN or more with a band still there
Bench.PILE_MIN = 30
Bench.PILE_PER_YEAR = 10
function Bench.tipping(run)
    local out = { piles = {} }
    local seasons = run.seasons
    local peak, lastPeak = -1, nil
    for s, r in ipairs(seasons) do
        if r.gone and not out.goneAt then out.goneAt = s end
        if not r.dead then
            if r.popEnd >= peak then peak, lastPeak = r.popEnd, s end
            if r.popEnd >= MAX_WORKERS and not out.capAt then out.capAt = s end
        end
    end
    local final = seasons[#seasons].popEnd
    if out.goneAt or (lastPeak and final <= peak - 2) then
        out.fall = out.goneAt and math.min(out.goneAt, (lastPeak or 0) + 1) or lastPeak + 1
        out.peak = peak
    end
    local years = math.floor(#seasons / 4)
    local yv = {}
    for y = 1, years do yv[y] = Bench.yearValues(run, y) end
    local best, bestYear = -1, nil
    for y = 1, years do
        if yv[y].goods > best then best, bestYear = yv[y].goods, y end
    end
    if years > 1 and bestYear and bestYear < years and yv[years].goods < best / 2 then out.collapse = bestYear + 1 end
    for _, k in ipairs({ 'storedFood', 'stockLogs', 'stockGold' }) do
        for y = 2, years - 1 do
            local a, b, c = yv[y - 1], yv[y], yv[y + 1]
            if c.alive == 1 and b[k] - a[k] >= Bench.PILE_PER_YEAR and c[k] - b[k] >= Bench.PILE_PER_YEAR and c[k] >= Bench.PILE_MIN then
                out.piles[k] = y
                break
            end
        end
    end
    return out
end

-- Report ------------------------------------------------------------------

local function fmt(s, places, scale)
    if not s or s.n == 0 then return '-' end
    return string.format('%.' .. (places or 1) .. 'f', s.mean * (scale or 1))
end

local function range(s)
    if not s or s.n == 0 then return '-' end
    return string.format('%d-%d', math.floor(s.min + 0.5), math.floor(s.max + 0.5))
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.floor((#list + 1) / 2)]
end

-- The short plain report: a table per strategy (yearly means over the seeds,
-- band with its min-max), the tipping points and the per-seed outliers.
function Bench.report(runs, years, meta)
    local agg, order = Bench.aggregate(runs, years)
    local out = {}
    local function p(...) out[#out + 1] = string.format(...) end
    p('Morphis sim bench: %s', meta and meta.label or '')
    p('%d s seasons, %d starting morphis (%s), %d seeds x %d years, player looks every %d s, step %.3f s',
        QUARTER_SECONDS, DIFFICULTIES[meta and meta.difficulty or 1].workers, DIFFICULTIES[meta and meta.difficulty or 1].name,
        meta and meta.seeds or 0, years, Bench.PLAYER_EVERY, Bench.DT)
    p('Means over seeds. alive = seeds with a band at year end; band = morphis at year end (min-max);')
    p('lost/migr per year; morale, >80, <30, idle, work as %% of morphi time; food/logs/gold delivered per season;')
    p('beds built; trades and fun per morphi per season; hard = hardships per season; stock at year end (logs/gold/stored food).')
    for _, strategy in ipairs(order) do
        p('')
        p('== %s ==', strategy)
        p('year alive  band      lost migr  morale >80  <30  idle work  food  logs  gold  beds trade fun   hard  stock l/g/f')
        for y = 1, years do
            local a = agg[strategy][y]
            p('%4d %5s  %-4s %-4s %4s %4s  %6s %4s %4s %5s %4s %5s %5s %5s %5s %5s %3s %6s  %s/%s/%s',
                y, fmt(a.alive, 0, a.alive.n) .. '/' .. a.alive.n, fmt(a.band, 1), range(a.band), fmt(a.lost), fmt(a.migrants),
                fmt(a.morale, 0), fmt(a.above80, 0, 100), fmt(a.below30, 0, 100), fmt(a.idle, 0, 100), fmt(a.work, 0, 100),
                fmt(a.food), fmt(a.logs), fmt(a.gold), fmt(a.beds), fmt(a.trades, 2), fmt(a.fun, 0), fmt(a.hardships),
                fmt(a.stockLogs, 0), fmt(a.stockGold, 0), fmt(a.storedFood, 0))
        end
    end
    -- tipping points
    p('')
    p('Tipping points (seeds tipping / seeds; median season or year where it starts):')
    for _, strategy in ipairs(order) do
        local n, falls, gone, collapse, cap = 0, {}, {}, {}, {}
        local piles = { storedFood = {}, stockLogs = {}, stockGold = {} }
        for _, run in ipairs(runs) do
            if run.strategy == strategy then
                n = n + 1
                local t = Bench.tipping(run)
                if t.fall then falls[#falls + 1] = t.fall end
                if t.goneAt then gone[#gone + 1] = t.goneAt end
                if t.collapse then collapse[#collapse + 1] = t.collapse end
                if t.capAt then cap[#cap + 1] = t.capAt end
                for k, y in pairs(t.piles) do piles[k][#piles[k] + 1] = y end
            end
        end
        local function s(list) local m = median(list); return m and Bench.seasonLabel(m) or '-' end
        local function y(list) local m = median(list); return m and ('Y' .. m) or '-' end
        p('  %-7s falls %d/%d (from %s), dies out %d/%d (%s), goods collapse %d/%d (%s), hits %d morphis %d/%d (%s)',
            strategy, #falls, n, s(falls), #gone, n, s(gone), #collapse, n, y(collapse), MAX_WORKERS, #cap, n, s(cap))
        p('  %-7s piling up: stored food %d/%d (%s), logs %d/%d (%s), gold %d/%d (%s)',
            '', #piles.storedFood, n, y(piles.storedFood), #piles.stockLogs, n, y(piles.stockLogs), #piles.stockGold, n, y(piles.stockGold))
    end
    -- outliers: seeds that died out, and final-year values 1.5 sd or more from the mean
    p('')
    p('Per-seed outliers: when each seed died out, and last-year band, goods per season or morale')
    p('1.5 sd or more from the strategy mean:')
    for _, strategy in ipairs(order) do
        local a = agg[strategy][years]
        local died, odd = {}, {}
        for _, run in ipairs(runs) do
            if run.strategy == strategy then
                local v = Bench.yearValues(run, years)
                local t = Bench.tipping(run)
                if t.goneAt then died[#died + 1] = run.seed .. ' ' .. Bench.seasonLabel(t.goneAt) end
                for _, k in ipairs({ 'band', 'goods', 'morale' }) do
                    local sm = a[k]
                    if v[k] and sm.n > 1 and sm.sd > 0 and math.abs(v[k] - sm.mean) >= 1.5 * sm.sd then
                        odd[#odd + 1] = string.format('%s %s %.1f (mean %.1f)', run.seed, k, v[k], sm.mean)
                    end
                end
            end
        end
        p('  %-7s died out: %s', strategy, #died > 0 and table.concat(died, ', ') or 'none')
        if #odd > 0 then p('  %-7s far from the mean: %s', '', table.concat(odd, ', ')) end
    end
    return table.concat(out, '\n') .. '\n'
end

-- CSV ---------------------------------------------------------------------

Bench.SEASON_COLUMNS = {
    'season', 'year', 'seasonInYear', 'popStart', 'popEnd', 'migrants', 'starved', 'left', 'gone', 'dead',
    'mSec', 'moraleSum', 'above80', 'below30', 'hungerSum', 'hungry', 'work', 'foodTime', 'rest', 'sulk', 'idle',
    'food', 'logs', 'gold', 'beds', 'trades', 'fun', 'complaints', 'hardships', 'hardHungry', 'hardBored', 'hardSlow', 'hardReach',
    'stockLogs', 'stockGold', 'storedFood', 'fedPct', 'drain', 'score', 'bushes', 'ripeBushes', 'trees', 'ore',
}

local function cell(v)
    if v == nil then return '' end
    if v == true then return '1' end
    if v == false then return '0' end
    if type(v) == 'number' then
        if v == math.floor(v) then return string.format('%d', v) end
        return string.format('%.4f', v)
    end
    return tostring(v)
end

-- Every season of every run: the raw counts (morphi-seconds and totals).
function Bench.seasonsCsv(runs)
    local lines = { 'strategy,seed,seasonSeconds,' .. table.concat(Bench.SEASON_COLUMNS, ',') }
    for _, run in ipairs(runs) do
        for _, r in ipairs(run.seasons) do
            local cells = { run.strategy, run.seed, cell(run.seasonSeconds) }
            for _, k in ipairs(Bench.SEASON_COLUMNS) do cells[#cells + 1] = cell(r[k]) end
            lines[#lines + 1] = table.concat(cells, ',')
        end
    end
    return table.concat(lines, '\n') .. '\n'
end

-- One line per strategy and year: mean, sd, min and max of every metric.
function Bench.yearsCsv(runs, years)
    local agg, order = Bench.aggregate(runs, years)
    local head = { 'strategy', 'year', 'seeds' }
    for _, k in ipairs(Bench.YEAR_METRICS) do
        for _, s in ipairs({ 'mean', 'sd', 'min', 'max' }) do head[#head + 1] = k .. '_' .. s end
    end
    local lines = { table.concat(head, ',') }
    for _, strategy in ipairs(order) do
        for y = 1, years do
            local a = agg[strategy][y]
            local cells = { strategy, cell(y), cell(a.alive.n) }
            for _, k in ipairs(Bench.YEAR_METRICS) do
                for _, s in ipairs({ 'mean', 'sd', 'min', 'max' }) do cells[#cells + 1] = cell(a[k][s]) end
            end
            lines[#lines + 1] = table.concat(cells, ',')
        end
    end
    return table.concat(lines, '\n') .. '\n'
end

-- Runs travel between processes as Lua source -------------------------------

local function ser(v, out)
    local t = type(v)
    if t == 'number' then
        if v ~= v then out[#out + 1] = '0/0'
        elseif v == math.huge then out[#out + 1] = 'math.huge'
        elseif v == -math.huge then out[#out + 1] = '-math.huge'
        elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format('%d', v)
        else out[#out + 1] = string.format('%.17g', v) end
    elseif t == 'string' then out[#out + 1] = string.format('%q', v)
    elseif t == 'boolean' then out[#out + 1] = tostring(v)
    elseif t == 'table' then
        out[#out + 1] = '{'
        local n = #v
        for i = 1, n do ser(v[i], out); out[#out + 1] = ',' end
        local keys = {}
        for k in pairs(v) do
            if type(k) == 'string' then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            out[#out + 1] = '[' .. string.format('%q', k) .. ']='
            ser(v[k], out)
            out[#out + 1] = ','
        end
        out[#out + 1] = '}'
    else out[#out + 1] = 'nil' end
end

function Bench.serialize(v)
    local out = {}
    ser(v, out)
    return table.concat(out)
end

function Bench.deserialize(s)
    return assert((loadstring or load)('return ' .. s))()
end

return Bench
