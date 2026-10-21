-- The simple players the sims use: a few storage spots by camp, and a
-- route clearer that mines and bridges the way to whatever is out of reach.
-- dofile('tools/sim_player.lua') after main.lua is loaded.
local Player = {}

-- Up to n sites of one kind on open ground in rings round camp, nearest first.
local function placeNearCamp(game, tool, siteKind, n)
    local w, ab = game.world, game.abilities
    local br = w.breakroom
    local placed = 0
    ab:select(tool)
    for r = 2, 8 do
        for dy = -r, r do
            for dx = -r, r do
                if placed >= n then return placed end
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = br.x + dx, br.y + dy
                    if w:isReachable(x, y) and w:canSite(siteKind, x, y) and ab:use(x, y) then placed = placed + 1 end
                end
            end
        end
    end
    return placed
end

function Player.placeStorage(game, n, bin)
    return placeNearCamp(game, bin and ABILITY_BIN or ABILITY_STORAGE, bin and SITE_BIN or SITE_STORAGE, n)
end

-- Beds, built and marked, and storage room still free (marked spots count).
function Player.bedCount(game)
    return #game.world.beds + #game.world:sitesOfKind(SITE_BED)
end

function Player.freeStorage(game)
    local w, n = game.world, 0
    for _, s in ipairs(w:storageTiles()) do n = n + math.max(0, w:freeSlots(s.x, s.y)) end
    for _, site in ipairs(w.sites) do n = n + (SITE_CAPACITY[site.kind] or 0) end
    return n
end

local function bandSize(game)
    local n = 0
    for _, wk in ipairs(game.workers) do if wk:isWorking() then n = n + 1 end end
    return n
end

-- A bed for every morphi in the band, one per call, while the logs last.
function Player.placeBeds(game)
    if Player.bedCount(game) < bandSize(game) and game.world:canAfford(COSTS.bed) then
        return placeNearCamp(game, ABILITY_BED, SITE_BED, 1)
    end
    return 0
end

-- The players tools/bench.lua compares. Each act() is one look at the map;
-- the bench calls it at the start and then every PLAYER_EVERY game seconds.
--   active  opens routes to what is out of reach, keeps storage free, a
--           bin when logs are spare, and a bed for every morphi
--   none    does nothing at all
--   dig     only mines and bridges routes (no storage, no beds)
--   beds    only builds beds (no digging or bridging, no storage)
Player.STRATEGIES = { 'active', 'none', 'dig', 'beds' }
Player.act = {
    active = function(game)
        Player.clearRoutes(game, 4)
        Player.placeBeds(game)
        if Player.freeStorage(game) < 4 then Player.placeStorage(game, 3) end
        if game.world.stock.logs >= COSTS.bin.logs + COSTS.bed.logs + 4 then Player.placeStorage(game, 1, true) end
    end,
    none = function() end,
    dig = function(game) Player.clearRoutes(game, 4) end,
    beds = function(game) Player.placeBeds(game) end,
}

-- The route clearer: each season, for the nearest few things out of reach
-- (bushes, trees, ore), the cheapest way through: grass is free, stone is
-- mined, water bridged while the logs last.
function Player.clearRoutes(game, n)
    local w, ab = game.world, game.abilities
    local reach = w:reachableFromBreakroom()
    local INF = math.huge
    local dist, prev = {}, {}
    local heap = {}
    local function key(x, y) return y * 1000 + x end
    local function push(d, x, y)
        heap[#heap + 1] = { d, x, y }
        local i = #heap
        while i > 1 and heap[math.floor(i / 2)][1] > heap[i][1] do
            heap[i], heap[math.floor(i / 2)] = heap[math.floor(i / 2)], heap[i]; i = math.floor(i / 2)
        end
    end
    local function pop()
        local top = heap[1]; heap[1] = heap[#heap]; heap[#heap] = nil
        local i = 1
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            if heap[l] and heap[l][1] < heap[m][1] then m = l end
            if heap[r] and heap[r][1] < heap[m][1] then m = r end
            if m == i then break end
            heap[i], heap[m] = heap[m], heap[i]; i = m
        end
        return top
    end
    for x = 1, w.w do for y = 1, w.h do
        if reach[x][y] then dist[key(x, y)] = 0; push(0, x, y) end
    end end
    local function cost(t)
        if t.passable then return 1 end
        if t.type == TILE_STONE or t.type == TILE_SNOW then return 4 end
        if t.type == TILE_WATER then return 6 end
        return nil
    end
    while #heap > 0 do
        local d, x, y = (table.unpack or unpack)(pop())
        if d <= (dist[key(x, y)] or INF) then
            for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
                local t = w:get(c[1], c[2])
                local k = t and cost(t)
                if k then
                    local nd = d + k
                    if nd < (dist[key(c[1], c[2])] or INF) then
                        dist[key(c[1], c[2])] = nd; prev[key(c[1], c[2])] = { x, y }; push(nd, c[1], c[2])
                    end
                end
            end
        end
    end
    local targets = {}
    for _, node in ipairs(w.nodes) do
        if not w:nodeReachable(node) and dist[key(node.x, node.y)] then
            targets[#targets + 1] = { node = node, d = dist[key(node.x, node.y)] }
        end
    end
    -- food first, like a sensible player, then whatever is nearest
    table.sort(targets, function(a, b)
        local fa, fb = a.node.kind == NODE_BUSH, b.node.kind == NODE_BUSH
        if fa ~= fb then return fa end
        return a.d < b.d
    end)
    local opened = 0
    for _, tg in ipairs(targets) do
        if opened >= n then break end
        local x, y = tg.node.x, tg.node.y
        local p = prev[key(x, y)]
        while p do
            local t = w:get(p[1], p[2])
            if t.type == TILE_STONE or t.type == TILE_SNOW then
                ab:select(ABILITY_MINE); ab:designateMine(p[1], p[2], p[1], p[2])
            elseif t.type == TILE_WATER and not t.site then
                ab:select(ABILITY_BRIDGE); ab:useLine(p[1], p[2], p[1], p[2])
            end
            p = prev[key(p[1], p[2])]
        end
        opened = opened + 1
    end
end

return Player
