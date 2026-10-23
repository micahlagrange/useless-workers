-- The simple players the sims use: a few storage spots by camp, and a
-- route clearer that mines and bridges the way to whatever is out of reach.
-- dofile('tools/sim_player.lua') after main.lua is loaded.
local JobSets = require('src.jobsets')
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

-- A nest for every morphi in the bunch, one per call, while the sticks,
-- grass and leaves last.
function Player.placeNests(game)
    -- a nest for every grown-up to nap in, and spare ones for eggs
    local want = bandSize(game) + 2
    if Player.bedCount(game) < want and game.world:canAfford(costOf(game.world, 'bed')) then
        return placeNearCamp(game, ABILITY_BED, SITE_BED, 1)
    end
    return 0
end
Player.placeBeds = Player.placeNests

-- Job management, the way a person would do it from the job screen (free
-- play only; arcade morphis have one fixed job). Each look: work waiting on
-- the queue that somebody could reach is counted by job; a job with work
-- waiting and nobody holding it as main or neutral goes to the morphi whose
-- main job has least to do, as its neutral job; and when one job has a pile
-- of work and somebody's main job has none, that morphi takes the busy job as
-- its main (at most one such change a look). Never a morphi's disliked job.
local function jobTypesOf(job)
    local out = {}
    for _, t in ipairs(JobSets.jobTypes(job)) do out[t] = true end
    return out
end

function Player.demand(game)
    local w, out = game.world, {}
    for _, job in ipairs(JobSets.JOBS) do
        local types, n = jobTypesOf(job), 0
        for _, j in ipairs(game.jobs.items) do
            if types[j.type] and ((j.node and j.node.ready and w:nodeReachable(j.node))
                or (j.site and not j.site.done and w:siteReachable(j.site))
                or (j.area and w:areaReachable(j.area))
                or (j.baby and j.baby.alive)) then
                n = n + 1
            end
        end
        out[job] = n
    end
    -- a sensible person keeps the bunch fed first: gathering only counts
    -- while the pile is short of what nests and baskets need
    local st = w.stock
    if (st.logs or 0) >= 20 and (st.grass or 0) >= 10 and (st.leaves or 0) >= 6 then out[ROLE_LUMBERJACK] = 0 end
    -- and food is always wanted while the stashes are not full
    if w:storedCount(ITEM_FOOD) < w:storageCapacity() then
        out[ROLE_FORAGER] = out[ROLE_FORAGER] * 2
        out[ROLE_HUNTER] = out[ROLE_HUNTER] * 2
    end
    return out
end

function Player.assignJobs(game)
    local band = {}
    for _, wk in ipairs(game.workers) do
        if wk.jobSet and wk:isWorking() then band[#band + 1] = wk end
    end
    if #band == 0 then return 0 end
    local demand = Player.demand(game)
    local changes = 0
    local function staffed(job)
        local n = 0
        for _, wk in ipairs(band) do
            if wk.jobSet.main == job or wk.jobSet.neutral == job then n = n + 1 end
        end
        return n
    end
    local function mains(job)
        local n = 0
        for _, wk in ipairs(band) do if wk.jobSet.main == job then n = n + 1 end end
        return n
    end
    -- the idlest morphi that can take this job, in the given slot
    local function idlest(job, slot)
        local best, bestD
        for _, wk in ipairs(band) do
            local js = wk.jobSet
            if js.disliked ~= job and js.main ~= job and js[slot] ~= job then
                -- leave a neutral alone that is the only cover for its job
                local keep = slot == 'neutral' and js.neutral and demand[js.neutral] > 0 and staffed(js.neutral) <= 1
                local d = demand[js.main] / math.max(1, mains(js.main))
                if not keep and (bestD == nil or d < bestD) then best, bestD = wk, d end
            end
        end
        return best
    end
    local jobs = {}
    for _, job in ipairs(JobSets.JOBS) do jobs[#jobs + 1] = job end
    table.sort(jobs, function(a, b) return demand[a] > demand[b] end)
    for _, job in ipairs(jobs) do
        if demand[job] > 0 and staffed(job) == 0 then
            local wk = idlest(job, 'neutral')
            if wk and wk:setJob('neutral', job) then changes = changes + 1 end
        end
    end
    -- one main job moved from an idle trade to the busiest one
    local busy = jobs[1]
    if demand[busy] >= 3 * math.max(1, mains(busy)) then
        for _, wk in ipairs(band) do
            local js = wk.jobSet
            if demand[js.main] == 0 and js.disliked ~= busy and js.main ~= busy and mains(js.main) >= 1 then
                if wk:setJob('main', busy) then changes = changes + 1 end
                break
            end
        end
    end
    return changes
end

-- Shinies hide in the clay: now and then mark a small patch of clay next to
-- open ground near home for the diggers, the way a person goes looking.
function Player.digForShinies(game)
    local w = game.world
    for _, site in ipairs(w.sites) do
        if site.kind == SITE_MINE and not site.done then return 0 end
    end
    local br = w.breakroom
    local reach = w:reachableFromBreakroom()
    for r = 2, 14 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = br.x + dx, br.y + dy
                    local t = w:get(x, y)
                    if t and (t.type == TILE_STONE or t.type == TILE_SNOW) and not t.site then
                        local open = false
                        for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
                            if w:inBounds(c[1], c[2]) and reach[c[1]][c[2]] then open = true end
                        end
                        if open then
                            game.abilities:select(ABILITY_MINE)
                            game.abilities:designateMine(x, y, x + 2, y + 2)
                            return 1
                        end
                    end
                end
            end
        end
    end
    return 0
end

-- The players tools/bench.lua compares. Each act() is one look at the map;
-- the bench calls it at the start and then every PLAYER_EVERY game seconds.
--   active  opens routes to what is out of reach, keeps storage free, a
--           bin when logs are spare, a bed for every morphi, and sees to
--           the band's jobs (assignJobs)
--   none    does nothing at all
--   dig     only mines and bridges routes (no storage, no beds)
--   nests   only weaves nests (no digging or bridging, no storage)
Player.STRATEGIES = { 'active', 'none', 'dig', 'nests' }
Player.act = {
    active = function(game)
        Player.assignJobs(game)
        Player.clearRoutes(game, 4)
        Player.digForShinies(game)
        Player.placeBeds(game)
        if Player.freeStorage(game) < 4 then Player.placeStorage(game, 3) end
        if game.world:canAfford(costOf(game.world, 'bin')) and (game.world.stock.grass or 0) >= 4 then Player.placeStorage(game, 1, true) end
    end,
    none = function() end,
    dig = function(game) Player.clearRoutes(game, 4) end,
    nests = function(game) Player.placeNests(game) end,
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
