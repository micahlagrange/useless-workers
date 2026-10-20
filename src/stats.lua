-- The run's audit log: what the band was like at the start of every day,
-- what the map looked like, what happened (arrivals, departures, deals) and
-- the milestones worth telling the player about at the end. Kept in memory
-- and written out as JSON for tools/stats_report.py and for Claude to read.
-- No LOVE calls in here, so the tests and the headless sim can use it.
require('src.constants')
local Scoring = require('src.scoring')

local Stats = {}
Stats.__index = Stats


-- One character per tile for the map snapshots. A node or a built site
-- shows over the ground under it.
Stats.TILE_CHARS = {
    water = '~', grass = '.', dirt = ',', stone = '#', snow = '*', bridge = '=',
    breakroom = 'C', wall = 'W', door = 'D',
}
Stats.NODE_CHARS = { bush = 'b', tree = 't', ore = 'g' }
Stats.LEGEND = {
    ['~'] = 'water', ['.'] = 'grass', [','] = 'dirt', ['#'] = 'stone', ['*'] = 'snow',
    ['='] = 'bridge', C = 'camp', W = 'wall', D = 'door', b = 'bush (ripe B)',
    t = 'tree (stump T)', g = 'gold ore', s = 'storage', n = 'bin', z = 'bed', ['+'] = 'site being built',
}

local function tileChar(t)
    if t.node then
        local c = Stats.NODE_CHARS[t.node.kind] or '?'
        if t.node.ready and t.node.kind == NODE_BUSH then return 'B' end
        if not t.node.ready and t.node.kind == NODE_TREE then return 'T' end
        return c
    end
    if t.site and not t.site.done then return '+' end
    if t.bed then return 'z' end
    if (t.storage or 0) > 1 then return 'n' end
    if (t.storage or 0) > 0 then return 's' end
    return Stats.TILE_CHARS[t.type] or '?'
end

-- The map as a list of strings, one per row.
function Stats.mapRows(world)
    local rows = {}
    for y = 1, world.h do
        local line = {}
        for x = 1, world.w do line[x] = tileChar(world.tiles[x][y]) end
        rows[y] = table.concat(line)
    end
    return rows
end

-- Milestones: each fires once, the first day its test passes. weight picks
-- between several that pass on the same day; the rest wait their turn.
-- s is the stats, r the day's row.
Stats.MILESTONES = {
    { id = 'year1', weight = 9, text = 'The band saw out its first year in the wilds.', test = function(s, r) return r.quarter > 4 end },
    { id = 'year2', weight = 9, text = 'Two years. The wilds are starting to feel like home.', test = function(s, r) return r.quarter > 8 end },
    { id = 'year3', weight = 9, text = 'Three years and still standing.', test = function(s, r) return r.quarter > 12 end },
    { id = 'year5', weight = 10, text = 'Five years. Morphis tell stories about this band.', test = function(s, r) return r.quarter > 20 end },
    { id = 'band8', weight = 6, text = 'Eight morphis around one campfire.', test = function(s, r) return r.pop >= 8 end },
    { id = 'band12', weight = 7, text = 'A dozen morphis. A proper village.', test = function(s, r) return r.pop >= 12 end },
    { id = 'gold50', weight = 5, text = 'Fifty gold dug out of the rock.', test = function(s, r) return r.gold >= 50 end },
    { id = 'gold200', weight = 7, text = 'Two hundred gold. The morphis are rich and have nothing to buy.', test = function(s, r) return r.gold >= 200 end },
    { id = 'logs100', weight = 5, text = 'A hundred logs felled.', test = function(s, r) return r.logs >= 100 end },
    { id = 'food200', weight = 5, text = 'Two hundred meals gathered.', test = function(s, r) return r.food >= 200 end },
    { id = 'food1000', weight = 8, text = 'A thousand meals gathered. Nobody counted the crumbs.', test = function(s, r) return r.food >= 1000 end },
    { id = 'trades10', weight = 4, text = 'Ten deals struck at camp.', test = function(s, r) return s.counts.trade >= 10 end },
    { id = 'arrivals10', weight = 4, text = 'Ten migrants took a chance on this band.', test = function(s, r) return s.counts.arrived >= 10 end },
}

-- meta: seed, mode, difficulty, build and anything else worth keeping
function Stats.new(meta)
    local self = setmetatable({}, Stats)
    self.meta = meta or {}
    self.meta.format = STATS_FORMAT
    self.meta.daySeconds = DAY_SECONDS
    self.meta.daysPerSeason = DAYS_PER_SEASON
    self.days = {}          -- one row per day, at its start
    self.maps = {}          -- maps[1] = full rows; later days: list of {x, y, char} changes
    self.events = {}
    self.milestones = {}
    self.fired = {}
    self.counts = { arrived = 0, starved = 0, left = 0, trade = 0, hardship = 0 }
    self.lastRows = nil
    self.lastMilestoneDay = -math.huge
    return self
end

-- Days follow the season clock, so day 10 is always the first of Summer.
-- A level's clock is not a season (arcade has none): its days just count
-- up from the start.
function Stats.dayOf(game)
    local scoring = game.scoring
    if scoring.quarterTimer > QUARTER_SECONDS then
        return math.floor((game.clock or 0) / DAY_SECONDS) + 1
    end
    local into = math.floor((QUARTER_SECONDS - scoring.quarterTimer) / DAY_SECONDS)
    into = math.min(math.max(into, 0), DAYS_PER_SEASON - 1)
    return (scoring.quarter - 1) * DAYS_PER_SEASON + into + 1
end

-- Something happened: kind is 'arrived', 'starved', 'left', 'trade',
-- 'hardship' or 'news'; who and text are optional.
function Stats:event(kind, game, who, text, tile)
    self.counts[kind] = (self.counts[kind] or 0) + 1
    self.events[#self.events + 1] = {
        day = Stats.dayOf(game), clock = math.floor((game.clock or 0) * 10 + 0.5) / 10,
        kind = kind, who = who, text = text, x = tile and tile.x, y = tile and tile.y,
    }
end

local function bucket(w)
    local s, g = w.state, w.goal
    if s == 'working' or (s == 'walking' and (g == 'work' or g == 'deliver')) then return 'work' end
    if s == 'eating' or (s == 'walking' and (g == 'eat' or g == 'fetch')) then return 'food' end
    if s == 'breaking' or s == 'trading' or (s == 'walking' and g == 'break') then return 'rest' end
    if s == 'sulking' then return 'sulk' end
    return 'idle'
end
Stats.bucket = bucket

local function round(v, places)
    local m = 10 ^ (places or 1)
    return math.floor(v * m + 0.5) / m
end

-- One row: the band, the stockpile and what has been gathered so far.
function Stats:row(game, day)
    local scoring, world = game.scoring, game.world
    local r = {
        day = day, clock = round(game.clock or 0),
        quarter = scoring.quarter,
        -- named from the day: the season label stops at Winter once the year is over
        season = scoring.quarterTimer > QUARTER_SECONDS and scoring:seasonLabel() or Stats.seasonOfDay(day),
        pop = 0, hunger = 0, morale = 0, hungry = 0, starving = 0, lowMorale = 0,
        work = 0, foodTime = 0, rest = 0, sulk = 0, idle = 0,
        roles = {},
        stockLogs = world.stock.logs, stockGold = world.stock.gold,
        storedFood = world:storedCount('food'),
        food = scoring.lifetimeDelivered.food or 0,
        logs = scoring.lifetimeDelivered.logs or 0,
        gold = scoring.lifetimeDelivered.gold or 0,
        arrived = self.counts.arrived, starved = self.counts.starved, left = self.counts.left,
        trades = self.counts.trade, hardships = self.counts.hardship,
        drain = round(scoring.drain, 2),
        ripeBushes = world:readyNodeCount(NODE_BUSH), trees = world:readyNodeCount(NODE_TREE), ore = world:readyNodeCount(NODE_ORE),
    }
    for _, w in ipairs(game.workers) do
        if w:isWorking() then
            r.pop = r.pop + 1
            r.hunger = r.hunger + w.hunger
            r.morale = r.morale + (w.morale or MORALE_MAX)
            if w.hunger < HUNGER_EAT_THRESHOLD then r.hungry = r.hungry + 1 end
            if w.hunger <= HUNGER_STARVING then r.starving = r.starving + 1 end
            if (w.morale or MORALE_MAX) < 30 then r.lowMorale = r.lowMorale + 1 end
            local b = bucket(w)
            if b == 'food' then b = 'foodTime' end
            r[b] = r[b] + 1
            r.roles[w.role] = (r.roles[w.role] or 0) + 1
        end
    end
    if r.pop > 0 then
        r.hunger = round(r.hunger / r.pop)
        r.morale = round(r.morale / r.pop)
    end
    return r
end

-- The map at the start of a day: the whole of it the first time, then
-- only the tiles that changed.
function Stats:snapshot(world)
    local rows = Stats.mapRows(world)
    if not self.lastRows then
        self.maps[#self.maps + 1] = { full = rows }
    else
        local changes = {}
        for y = 1, #rows do
            local a, b = self.lastRows[y], rows[y]
            if a ~= b then
                for x = 1, #b do
                    local c = b:sub(x, x)
                    if a:sub(x, x) ~= c then changes[#changes + 1] = { x, y, c } end
                end
            end
        end
        self.maps[#self.maps + 1] = { changes = changes }
    end
    self.lastRows = rows
end

-- The map rows on a given day (1 = the first), rebuilt from the changes.
function Stats.mapOn(maps, day)
    if not maps[1] then return nil end
    local grid = {}
    for y, line in ipairs(maps[1].full) do
        grid[y] = {}
        for x = 1, #line do grid[y][x] = line:sub(x, x) end
    end
    for d = 2, math.min(day, #maps) do
        for _, c in ipairs(maps[d].changes or {}) do grid[c[2]][c[1]] = c[3] end
    end
    local rows = {}
    for y, cells in ipairs(grid) do rows[y] = table.concat(cells) end
    return rows
end

function Stats.seasonOfDay(day)
    return Scoring.seasonName(math.floor((day - 1) / DAYS_PER_SEASON) + 1)
end

function Stats:mapOnDay(day)
    return Stats.mapOn(self.maps, day)
end

function Stats:checkMilestones(r)
    if r.day - self.lastMilestoneDay < MILESTONE_GAP_DAYS then return nil end
    local best
    for _, m in ipairs(Stats.MILESTONES) do
        if not self.fired[m.id] and m.test(self, r) and (not best or m.weight > best.weight) then best = m end
    end
    if not best then return nil end
    self.fired[best.id] = true
    self.lastMilestoneDay = r.day
    -- anything else that passed today is past news by the next one
    for _, m in ipairs(Stats.MILESTONES) do
        if not self.fired[m.id] and m.weight < best.weight and m.test(self, r) then self.fired[m.id] = 'skipped' end
    end
    local ms = { id = best.id, day = r.day, season = r.season, text = best.text }
    self.milestones[#self.milestones + 1] = ms
    return ms
end

-- Call every frame of play with the game table. Records a row and a map
-- for each day that has started since the last call, and returns any
-- milestone reached.
function Stats:update(game)
    local reached
    local today = Stats.dayOf(game)
    while #self.days < today do
        local day = #self.days + 1
        local r = self:row(game, day)
        self.days[day] = r
        self:snapshot(game.world)
        reached = self:checkMilestones(r) or reached
    end
    return reached
end

-- The run as a plain read, for the HISTORY screen: milestones and the
-- comings and goings, oldest first.
function Stats:history()
    local lines = {}
    local list = {}
    for _, m in ipairs(self.milestones) do list[#list + 1] = { day = m.day, order = 0, text = m.text } end
    for _, e in ipairs(self.events) do
        if e.kind == 'arrived' then
            list[#list + 1] = { day = e.day, order = 1, text = (e.who or 'A migrant') .. ' arrived.' }
        elseif e.kind == 'starved' then
            list[#list + 1] = { day = e.day, order = 1, text = (e.who or 'A morphi') .. ' starved and wandered off.' }
        elseif e.kind == 'left' then
            list[#list + 1] = { day = e.day, order = 1, text = (e.who or 'A morphi') .. ' had enough and left.' }
        end
    end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        return a.order < b.order
    end)
    for _, it in ipairs(list) do
        lines[#lines + 1] = string.format('Day %d (%s): %s', it.day, Stats.seasonOfDay(it.day), it.text)
    end
    return lines
end

-- JSON -----------------------------------------------------------------------

local function encodeString(s)
    s = s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        if c == '\n' then return '\\n' end
        if c == '\t' then return '\\t' end
        return string.format('\\u%04x', c:byte())
    end)
    return '"' .. s .. '"'
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local function encode(v, out)
    local kind = type(v)
    if kind == 'nil' then out[#out + 1] = 'null'
    elseif kind == 'boolean' then out[#out + 1] = tostring(v)
    elseif kind == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = 'null'
        elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format('%d', v)
        else out[#out + 1] = string.format('%.4g', v) end
    elseif kind == 'string' then out[#out + 1] = encodeString(v)
    elseif kind == 'table' then
        local arr, n = isArray(v)
        if arr and n > 0 then
            out[#out + 1] = '['
            for i = 1, n do
                if i > 1 then out[#out + 1] = ',' end
                encode(v[i], out)
            end
            out[#out + 1] = ']'
        else
            local keys = {}
            for k in pairs(v) do if type(k) == 'string' then keys[#keys + 1] = k end end
            table.sort(keys)
            out[#out + 1] = '{'
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = ',' end
                out[#out + 1] = encodeString(k)
                out[#out + 1] = ':'
                encode(v[k], out)
            end
            out[#out + 1] = '}'
        end
    else out[#out + 1] = 'null' end
end

function Stats.json(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

-- The whole run as JSON. blurb is the player's few words on what was fun
-- and what was not, cut to STATS_BLURB_MAX characters.
function Stats:export(blurb, extra)
    local meta = {}
    for k, v in pairs(self.meta) do meta[k] = v end
    for k, v in pairs(extra or {}) do meta[k] = v end
    blurb = blurb or ''
    if #blurb > STATS_BLURB_MAX then blurb = blurb:sub(1, STATS_BLURB_MAX) end
    meta.blurb = blurb
    -- one row per day, then the newline-free blob; the map lines on their own
    -- keep the file readable in a text editor
    local legend = {}
    for c, name in pairs(Stats.LEGEND) do legend[c] = name end
    return Stats.json({
        meta = meta, legend = legend, days = self.days, maps = self.maps,
        events = self.events, milestones = self.milestones, counts = self.counts,
        history = self:history(),
    })
end

return Stats
