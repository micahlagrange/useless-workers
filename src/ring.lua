-- The radial tool. A tap on the meadow opens a ring of Toybox buttons around
-- the thing tapped, with only what makes sense there; a caption plate at the
-- bottom says what it is. Replaces the tool tray and the SELECT tool.
--
-- Ring.forTile / Ring.forWorker only describe a ring (testable without
-- LOVE). Each item has an id that main.lua acts on:
--   build:<tool>   set out a stash / basket / nest / wall / door here
--   dig, digpatch  mark this clay, or its connected patch (up to 16)
--   unmark, unmarkall
--   bridge         a bridge square on this water
--   calloff        take back a site nobody has started on
--   takeaway       take away a finished stash / basket / nest
--   look:<n>       go to the bunch's n-th morphi (the home nest's ring)
--   job:<job>      tap: first job; hold: then job (a morphi's ring)
--   follow         the middle of a morphi's ring
require('src.constants')
local JobSets = require('src.jobsets')

local Ring = {}
Ring.__index = Ring

Ring.PATCH_MAX = 16
Ring.HOLD_SECONDS = 0.45

local BUILD_ICON = { storage = 'stash', bin = 'basket', bed = 'nest', wall = 'wall', door = 'door' }
local BUILD_LABEL = { storage = 'Stash', bin = 'Basket', bed = 'Nest', wall = 'Wall', door = 'Door' }
local BUILD_BLURB = { storage = 'holds 1 thing', bin = 'holds 4', bed = 'naps here are shorter', wall = 'keeps the bunch in', door = 'a way through a wall' }
Ring.BUILD_ICON, Ring.BUILD_LABEL = BUILD_ICON, BUILD_LABEL

local function cap(s) return (s:gsub('^%l', string.upper)) end

local function isClay(t) return t and (t.type == TILE_STONE or t.type == TILE_SNOW) end
Ring.isClay = isClay

-- What is missing to pay for a cost: 'needs 1 leaf', or nil when affordable.
local WORDS = { logs = { 'stick', 'sticks' }, grass = { 'grass', 'grass' }, leaves = { 'leaf', 'leaves' }, gold = { 'shiny', 'shinies' } }
function Ring.missing(world, cost)
    for _, k in ipairs({ 'logs', 'grass', 'leaves', 'gold' }) do
        local need = (cost[k] or 0) - (world.stock[k] or 0)
        if need > 0 then return 'needs ' .. need .. ' ' .. WORDS[k][need == 1 and 1 or 2] end
    end
    return nil
end

local function costLabel(world, kind)
    local w = costWords(costOf(world, kind), ', ')
    return w == '' and 'free' or w
end

-- The connected patch of unmarked clay from (x, y), up to max squares,
-- nearest first.
function Ring.patch(world, x, y, max, test)
    test = test or function(t) return isClay(t) and not t.site end
    max = max or Ring.PATCH_MAX
    local out, seen, queue, head = {}, {}, { { x = x, y = y } }, 1
    while head <= #queue and #out < max do
        local p = queue[head]
        head = head + 1
        local k = p.x * 100000 + p.y
        if not seen[k] then
            seen[k] = true
            local t = world:get(p.x, p.y)
            if t and test(t) then
                out[#out + 1] = p
                queue[#queue + 1] = { x = p.x + 1, y = p.y }
                queue[#queue + 1] = { x = p.x - 1, y = p.y }
                queue[#queue + 1] = { x = p.x, y = p.y + 1 }
                queue[#queue + 1] = { x = p.x, y = p.y - 1 }
            end
        end
    end
    return out
end

-- The ring for a tap on tile (tx, ty), or nil and a caption when the tile
-- only has something to say (a bush, a tree, a built bridge).
-- tools: the game's tool list (ABILITY_ORDER), so arcade gets walls and doors.
function Ring.forTile(world, tx, ty, tools)
    local t = world:get(tx, ty)
    if not t then return nil end
    local spec = { kind = 'tile', tile = { x = tx, y = ty, w = 1, h = 1 }, items = {} }
    local items = spec.items
    local has = {}
    for _, tool in ipairs(tools or ABILITY_ORDER) do has[tool] = true end

    -- the home nest: the bunch, as faces to jump to
    if t.type == TILE_BREAKROOM and world.breakroom then
        spec.kind = 'home'
        spec.tile = { x = world.breakroom.x, y = world.breakroom.y, w = 2, h = 2 }
        spec.caption = { title = 'The home nest', line = 'Sticks and shinies come here. Tap a blob to go to it.' }
        return spec
    end

    -- a site: call it off (gives back the cost if nobody has started)
    if t.site and t.site.kind ~= SITE_MINE then
        local s = t.site
        local name = s.kind == SITE_BRIDGE and 'Bridge' or (BUILD_LABEL[s.kind] or cap(s.kind))
        spec.tile = { x = s.x, y = s.y, w = s.kind == SITE_BIN and 2 or 1, h = 1 }
        spec.kind = 'site'
        items[#items + 1] = { id = 'calloff', icon = 'trash', label = 'Call off', cost = s.working and nil or 'gives back', off = s.working and true or nil,
            why = s.working and 'Someone is already building that' or nil }
        local p = Ring.siteProgress(s)
        spec.caption = { title = name .. ' (being built)', line = s.working and ('A builder is on it: ' .. math.floor(p * 100) .. '% done.') or 'Waiting for a builder.' }
        return spec
    end

    -- clay
    if isClay(t) then
        spec.kind = 'clay'
        if t.site and t.site.kind == SITE_MINE then
            items[#items + 1] = { id = 'unmark', icon = 'unmark', label = 'Unmark', off = t.site.working and true or nil, why = t.site.working and 'A digger is on it' or nil }
            items[#items + 1] = { id = 'unmarkall', icon = 'patch', label = 'Unmark all' }
            spec.caption = { title = 'Marked for digging', line = 'A digger digs it once a square next to it can be reached.', hint = 'Drag from a marked square to wipe marks.' }
        else
            local n = #Ring.patch(world, tx, ty)
            items[#items + 1] = { id = 'dig', icon = 'dig', label = 'Dig', preview = 'mark' }
            items[#items + 1] = { id = 'digpatch', icon = 'patch', label = 'Dig patch', cost = tostring(n) }
            spec.caption = { title = 'Clay', line = 'Shinies hide in clay. Diggers only find them by digging.', hint = 'Drag across clay to mark lots in one go.' }
        end
        return spec
    end

    -- water
    if t.type == TILE_WATER then
        spec.kind = 'water'
        local missing = Ring.missing(world, costOf(world, 'bridge'))
        items[#items + 1] = { id = 'bridge', icon = 'bridge', label = 'Bridge', preview = SITE_BRIDGE, cost = missing or costLabel(world, 'bridge'), off = missing and true or nil, why = missing and ('A bridge ' .. missing) or nil }
        spec.caption = { title = 'A stream', line = 'Plenty of good things sit on the far bank.', hint = 'Drag across the water to lay a whole bridge, a square at a time.' }
        return spec
    end
    if t.type == TILE_BRIDGE then
        return nil, { title = 'A bridge', line = 'Built. The bunch can cross here.' }
    end

    -- things that stand on a tile
    if t.node then
        local k = t.node.kind
        if k == NODE_BUSH then return nil, { title = 'A berry bush', line = 'Foragers pick it when it is ripe; hungry blobs snack straight off it.' } end
        if k == NODE_TREE then return nil, { title = 'A tree', line = 'Gatherers bring sticks from it. It grows back.' } end
        if k == NODE_GRASS then return nil, { title = 'A tuft of grass', line = 'Gatherers bring it home for baskets, nests and baby washes.' } end
        if k == NODE_LEAVES then return nil, { title = 'Leaves', line = 'Gatherers bring them home for nests.' } end
        if k == NODE_CRITTER then return nil, { title = 'A critter', line = 'Hunters chase it for meat.' } end
        return nil, { title = cap(tostring(k)), line = '' }
    end

    -- something finished: take it away
    local part = t.binPart and world:get(t.binPart.x, t.binPart.y)
    local built = (part and 'bin') or (t.storage >= (STORAGE_BIN_CAPACITY or 4) and 'bin') or (t.storage > 0 and 'storage') or (t.bed and 'bed') or nil
    if built then
        local base = part and { x = t.binPart.x, y = t.binPart.y } or { x = tx, y = ty }
        local bt = world:get(base.x, base.y)
        spec.kind = 'built'
        spec.tile = { x = base.x, y = base.y, w = built == 'bin' and 2 or 1, h = 1 }
        local holding = #(bt.items or {})
        local busy = holding > 0 or bt.restingBy ~= nil
        items[#items + 1] = { id = 'takeaway', icon = 'trash', label = 'Take away', off = busy or nil,
            why = holding > 0 and 'Empty it first: it is holding food' or (bt.restingBy and 'Someone is napping there') or nil }
        local line
        if built == 'bed' then line = 'Naps here are shorter and do more good.'
        else line = 'Holds ' .. holding .. ' of ' .. bt.storage .. '.' end
        spec.caption = { title = BUILD_LABEL[built], line = line }
        return spec
    end
    if t.type == TILE_WALL or t.type == TILE_DOOR then
        return nil, { title = t.type == TILE_WALL and 'A wall' or 'A door', line = 'Built.' }
    end

    -- open ground: set something out
    spec.kind = 'grass'
    for _, tool in ipairs({ ABILITY_STORAGE, ABILITY_BIN, ABILITY_BED, ABILITY_WALL, ABILITY_DOOR }) do
        if has[tool] then
            local kind = SITE_FOR_TOOL[tool]
            local missing = Ring.missing(world, costOf(world, kind))
            local fits, why = world:canSite(kind, tx, ty)
            local off = missing ~= nil or not fits
            items[#items + 1] = {
                id = 'build:' .. tool, icon = BUILD_ICON[kind], label = BUILD_LABEL[kind], preview = kind,
                cost = missing or (not fits and 'no room') or costLabel(world, kind), off = off or nil,
                why = missing and ('A ' .. BUILD_LABEL[kind]:lower() .. ' ' .. missing) or (not fits and (BUILD_LABEL[kind] .. ' ' .. (why or 'needs room'))) or nil,
            }
        end
    end
    local blurbs = {}
    for _, it in ipairs(items) do blurbs[#blurbs + 1] = it.label:lower() .. ' ' .. BUILD_BLURB[it.preview] end
    spec.caption = { title = 'Open grass', line = 'Set something out here. A builder makes it.', hint = table.concat(blurbs, ', ') .. '.' }
    return spec
end

-- The ring for a tap on a morphi: its six jobs. Arcade morphis have one
-- fixed job, babies and eggs have none (nil: main.lua opens what fits).
function Ring.forWorker(w)
    if not (w and w.alive and w.jobSet) then return nil end
    local js = w.jobSet
    local spec = { kind = 'morphi', worker = w, items = {} }
    for _, job in ipairs(JobSets.JOBS) do
        local item = { id = 'job:' .. job, icon = job, label = ROLES[job].label, hold = true }
        if job == js.main then item.on, item.badge = true, '1'
        elseif job == js.neutral then item.neutral, item.badge = true, '2'
        elseif job == js.disliked then item.off, item.badge, item.badgeColor = true, '!', 'berry' end
        spec.items[#spec.items + 1] = item
    end
    spec.center = { id = 'follow', icon = 'follow' }
    return spec
end

-- How far along a site is, 0 to 1: its builder's work so far.
function Ring.siteProgress(site)
    local w = site.claimedBy
    if type(w) ~= 'table' or not (w.state == 'working' and w.targetSite == site) then return 0 end
    return math.max(0, math.min(1, 1 - (w.stateTimer or 0) / BUILD_SECONDS))
end

-- Layout -------------------------------------------------------------------

function Ring.radius(n, tap)
    tap = tap or 56
    local r = n <= 2 and 84 or n <= 3 and 88 or n <= 5 and 96 or 108
    -- many faces (a big bunch): wide enough that buttons don't touch
    return math.max(r, n * (tap + 26) / (2 * math.pi))
end

-- Offsets of each item from the ring's centre, in the mockup's angles: one
-- straight up, two and three fanned over the top, four or more all round.
function Ring.offsets(n, tap)
    local R = Ring.radius(n, tap)
    local start = n == 1 and -90 or n == 2 and -150 or n == 3 and -180 or -90
    local span = n == 2 and 120 or n == 3 and 180 or 360
    local out = {}
    for i = 1, n do
        local a
        if n == 1 then a = -90
        elseif span == 360 then a = start + (i - 1) * 360 / n
        else a = start + (i - 1) * span / (n - 1) end
        a = math.rad(a)
        out[i] = { x = math.cos(a) * R, y = math.sin(a) * R, up = math.sin(a) < -0.3 }
    end
    return out, R
end

return Ring
