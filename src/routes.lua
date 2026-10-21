-- Routes the band opens by itself. A morphi with nothing of its trade in
-- reach picks the nearest thing of its trade that is out of reach and marks
-- the cheapest way there: grass is walked, stone and snow are marked for
-- mining, water is bridged (paid in logs from the stockpile, like the
-- player's BRIDGE tool). One route at a time, so the band does not tunnel
-- all over the map.
require('src.constants')

local Routes = {}

local function key(x, y) return y * 1000 + x end

local function stepCost(t)
    if t.passable then return 1 end
    if t.site then return nil end -- somebody's mark is already there; go round
    if t.type == TILE_STONE or t.type == TILE_SNOW then return 4 end
    if t.type == TILE_WATER then return 6 end
    return nil
end

-- Cheapest-route tree out of the reachable ground: dist and prev by key.
local function spread(world)
    local reach = world:reachableFromBreakroom()
    local dist, prev, heap = {}, {}, {}
    local function push(d, x, y)
        heap[#heap + 1] = { d, x, y }
        local i = #heap
        while i > 1 and heap[math.floor(i / 2)][1] > heap[i][1] do
            heap[i], heap[math.floor(i / 2)] = heap[math.floor(i / 2)], heap[i]
            i = math.floor(i / 2)
        end
    end
    local function pop()
        local top = heap[1]
        heap[1] = heap[#heap]; heap[#heap] = nil
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
    for x = 1, world.w do
        for y = 1, world.h do
            if reach[x] and reach[x][y] then dist[key(x, y)] = 0; push(0, x, y) end
        end
    end
    while #heap > 0 do
        local top = pop()
        local d, x, y = top[1], top[2], top[3]
        if d <= (dist[key(x, y)] or math.huge) then
            for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
                local t = world:get(c[1], c[2])
                local k = t and stepCost(t)
                if k then
                    local nd = d + k
                    if nd < (dist[key(c[1], c[2])] or math.huge) then
                        dist[key(c[1], c[2])] = nd
                        prev[key(c[1], c[2])] = { x, y }
                        push(nd, c[1], c[2])
                    end
                end
            end
        end
    end
    return dist, prev
end

-- Is the last route the band marked still being dug or built?
function Routes.pending(world)
    for _, site in ipairs(world.selfRouteSites or {}) do
        if not site.done then return true end
    end
    return false
end

-- Mark a way to the nearest unreachable node of `kind` (or of any kind when
-- nil). Returns the node it opens the way to, or nil when there is nothing
-- to open, a route is already in progress, or the logs do not cover the
-- water on every candidate route.
function Routes.open(world, jobs, kind, maxRoute)
    if Routes.pending(world) then return nil end
    local dist, prev = spread(world)
    local targets = {}
    for _, node in ipairs(world.nodes) do
        if node.ready and (kind == nil or node.kind == kind) and not world:nodeReachable(node) then
            local d = dist[key(node.x, node.y)]
            if d and d <= (maxRoute or math.huge) then targets[#targets + 1] = { node = node, d = d } end
        end
    end
    table.sort(targets, function(a, b) return a.d < b.d end)
    for _, tg in ipairs(targets) do
        local stone, water = {}, {}
        local p = prev[key(tg.node.x, tg.node.y)]
        while p do
            local t = world:get(p[1], p[2])
            if t.type == TILE_STONE or t.type == TILE_SNOW then
                stone[#stone + 1] = { x = p[1], y = p[2] }
            elseif t.type == TILE_WATER then
                water[#water + 1] = { x = p[1], y = p[2] }
            end
            p = prev[key(p[1], p[2])]
        end
        if #stone + #water > 0 and (#water == 0 or world:spend({ logs = #water * COSTS.bridge.logs })) then
            local sites = {}
            if #stone > 0 then
                local area = world:newArea()
                for _, s in ipairs(stone) do
                    local site = world:addSite(SITE_MINE, s.x, s.y, area)
                    if site then sites[#sites + 1] = site end
                end
                if #area.sites > 0 then jobs:postArea(area) else world:removeArea(area) end
            end
            for _, s in ipairs(water) do
                local site = world:addSite(SITE_BRIDGE, s.x, s.y)
                if site then
                    sites[#sites + 1] = site
                    jobs:postSite(site)
                end
            end
            if #sites > 0 then
                world.selfRouteSites = sites
                return tg.node
            end
        end
    end
    return nil
end

return Routes
