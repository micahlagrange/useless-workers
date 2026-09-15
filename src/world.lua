require('src.constants')
local Util = require('src.util')
local Noise = require('src.noise')

local World = {}
World.__index = World

local function newTile(kind, altitude)
    return { type = kind, altitude = altitude or 0.5, passable = PASSABLE[kind] or false, node = nil, item = nil, site = nil, storage = false, reservedBy = nil, colorSeed = 0.5 }
end

function World.new(w, h, rng)
    local self = setmetatable({}, World)
    self.w, self.h = w or WORLD_W, h or WORLD_H
    self.rng = rng
    self.tiles = {}
    self.nodes = {}
    self.nextNodeId = 1
    self.items = {}
    self.nextItemId = 1
    self.sites = {}
    self.nextSiteId = 1
    self.areas = {}
    self.nextAreaId = 1
    self.storageList = {}
    self.stock = { logs = 0, gold = 0 }
    self.version = 0
    self.breakroom = nil
    self.reachCache = nil
    self.reachCacheVersion = -1
    self.onTileChanged = nil
    self.bands = { water = 0.2, grass = 0.6, stone = 0.95 }
    for x = 1, self.w do
        self.tiles[x] = {}
        for y = 1, self.h do
            self.tiles[x][y] = newTile(TILE_GRASS, 0.5)
        end
    end
    return self
end

-- Noise world: altitude per tile, then the map is cut by quantiles so every seed
-- has roughly the same mix of water, grass, stone and snow.
function World.generate(seedNumber, rng, w, h)
    local self = World.new(w, h, rng)
    local noise = Noise.new(seedNumber, NOISE_BASE_FREQUENCY, NOISE_OCTAVES)
    local values = {}
    for x = 1, self.w do
        for y = 1, self.h do
            local a = noise:value(x, y)
            self.tiles[x][y].altitude = a
            values[#values + 1] = a
        end
    end
    table.sort(values)
    local function quantile(q)
        local i = Util.clamp(math.floor(q * #values) + 1, 1, #values)
        return values[i]
    end
    self.bands = {
        water = quantile(WORLD_MIX.water),
        grass = quantile(WORLD_MIX.water + WORLD_MIX.grass),
        stone = quantile(WORLD_MIX.water + WORLD_MIX.grass + WORLD_MIX.stone),
    }
    for x = 1, self.w do
        for y = 1, self.h do
            local t = self.tiles[x][y]
            local kind
            if t.altitude < self.bands.water then
                kind = TILE_WATER
            elseif t.altitude < self.bands.grass then
                kind = TILE_GRASS
            elseif t.altitude < self.bands.stone then
                kind = TILE_STONE
            else
                kind = TILE_SNOW
            end
            t.type = kind
            t.passable = PASSABLE[kind] or false
            t.colorSeed = rng:random()
        end
    end
    self:placeBreakroom()
    self.version = self.version + 1
    return self
end

-- Hand built worlds for tests.
-- '.' grass  '#' stone  '~' water  'B' break room  'b' ripe bush  'T' tree  'G' gold ore (in stone)  'S' built storage tile
function World.fromGrid(rows, rng)
    local h = #rows
    local w = #rows[1]
    local self = World.new(w, h, rng)
    local breakroomTiles = {}
    local nodeTiles = {}
    local storageTiles = {}
    for y = 1, h do
        for x = 1, w do
            local ch = rows[y]:sub(x, x)
            local kind = TILE_GRASS
            if ch == '#' or ch == 'G' then kind = TILE_STONE
            elseif ch == '~' then kind = TILE_WATER
            elseif ch == 'B' then kind = TILE_BREAKROOM; breakroomTiles[#breakroomTiles + 1] = { x = x, y = y }
            end
            if ch == 'b' then nodeTiles[#nodeTiles + 1] = { kind = NODE_BUSH, x = x, y = y }
            elseif ch == 'T' then nodeTiles[#nodeTiles + 1] = { kind = NODE_TREE, x = x, y = y }
            elseif ch == 'G' then nodeTiles[#nodeTiles + 1] = { kind = NODE_ORE, x = x, y = y }
            end
            local t = self.tiles[x][y]
            t.type = kind
            t.passable = PASSABLE[kind] or false
            if ch == 'S' then storageTiles[#storageTiles + 1] = { x = x, y = y } end
        end
    end
    if #breakroomTiles > 0 then
        local first = breakroomTiles[1]
        self.breakroom = { x = first.x, y = first.y, tiles = breakroomTiles }
        self.breakroom.cx = (first.x - 1) * TILE_SIZE + TILE_SIZE
        self.breakroom.cy = (first.y - 1) * TILE_SIZE + TILE_SIZE
    end
    for _, n in ipairs(nodeTiles) do
        local node = self:addNode(n.kind, n.x, n.y)
        node.ready = true
    end
    for _, st in ipairs(storageTiles) do self:markStorage(st.x, st.y) end
    self.version = self.version + 1
    return self
end

function World:inBounds(x, y)
    return x >= 1 and y >= 1 and x <= self.w and y <= self.h
end

function World:get(x, y)
    if not self:inBounds(x, y) then return nil end
    return self.tiles[x][y]
end

function World:isPassable(x, y)
    local t = self:get(x, y)
    return t ~= nil and t.passable == true
end

function World:setType(x, y, kind)
    local t = self:get(x, y)
    if not t then return false end
    t.type = kind
    t.passable = PASSABLE[kind] or false
    if self.rng then t.colorSeed = self.rng:random() end
    self.version = self.version + 1
    self.reachCache = nil
    if self.onTileChanged then self.onTileChanged(x, y, kind) end
    return true
end

-- Player tools -----------------------------------------------------------

function World:dig(x, y)
    local t = self:get(x, y)
    if t and t.type == TILE_STONE then
        return self:setType(x, y, TILE_DIRT)
    end
    return false
end

function World:explode(x, y, radius)
    radius = radius or 1
    local count = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local t = self:get(x + dx, y + dy)
            if t and (t.type == TILE_STONE or t.type == TILE_SNOW) then
                self:setType(x + dx, y + dy, TILE_DIRT)
                count = count + 1
            end
        end
    end
    return count
end

function World:bridge(x, y)
    local t = self:get(x, y)
    if t and t.type == TILE_WATER then
        return self:setType(x, y, TILE_BRIDGE)
    end
    return false
end

-- Axis aligned run of tiles from (x1, y1) toward (x2, y2), longest axis wins.
function World:lineTiles(x1, y1, x2, y2, maxLength)
    maxLength = maxLength or LINE_MAX_LENGTH
    local dx, dy = x2 - x1, y2 - y1
    local tiles = {}
    if math.abs(dx) >= math.abs(dy) then
        local step = Util.sign(dx)
        local n = math.min(math.abs(dx), maxLength - 1)
        for i = 0, n do
            local x = x1 + i * step
            if self:inBounds(x, y1) then tiles[#tiles + 1] = { x = x, y = y1 } end
        end
    else
        local step = Util.sign(dy)
        local n = math.min(math.abs(dy), maxLength - 1)
        for i = 0, n do
            local y = y1 + i * step
            if self:inBounds(x1, y) then tiles[#tiles + 1] = { x = x1, y = y } end
        end
    end
    return tiles
end

function World:countType(tiles, kind)
    local n = 0
    for _, p in ipairs(tiles) do
        local t = self:get(p.x, p.y)
        if t and t.type == kind then n = n + 1 end
    end
    return n
end

-- Regions and reachability ----------------------------------------------

function World:computeRegions()
    local label = {}
    for x = 1, self.w do label[x] = {} end
    local sizes = {}
    local id = 0
    for sx = 1, self.w do
        for sy = 1, self.h do
            if self.tiles[sx][sy].passable and not label[sx][sy] then
                id = id + 1
                sizes[id] = 0
                local stack = { { sx, sy } }
                label[sx][sy] = id
                while #stack > 0 do
                    local p = table.remove(stack)
                    sizes[id] = sizes[id] + 1
                    local px, py = p[1], p[2]
                    local neighbours = { { px + 1, py }, { px - 1, py }, { px, py + 1 }, { px, py - 1 } }
                    for _, q in ipairs(neighbours) do
                        local qx, qy = q[1], q[2]
                        if self:inBounds(qx, qy) and self.tiles[qx][qy].passable and not label[qx][qy] then
                            label[qx][qy] = id
                            stack[#stack + 1] = { qx, qy }
                        end
                    end
                end
            end
        end
    end
    return label, sizes
end

function World:reachableFromBreakroom()
    if self.reachCache and self.reachCacheVersion == self.version then
        return self.reachCache
    end
    local reach = {}
    for x = 1, self.w do reach[x] = {} end
    if self.breakroom then
        local start = self.breakroom.tiles[1]
        local stack = { { start.x, start.y } }
        reach[start.x][start.y] = true
        while #stack > 0 do
            local p = table.remove(stack)
            local px, py = p[1], p[2]
            local neighbours = { { px + 1, py }, { px - 1, py }, { px, py + 1 }, { px, py - 1 } }
            for _, q in ipairs(neighbours) do
                local qx, qy = q[1], q[2]
                if self:inBounds(qx, qy) and self.tiles[qx][qy].passable and not reach[qx][qy] then
                    reach[qx][qy] = true
                    stack[#stack + 1] = { qx, qy }
                end
            end
        end
    end
    self.reachCache = reach
    self.reachCacheVersion = self.version
    return reach
end

function World:isReachable(x, y)
    local reach = self:reachableFromBreakroom()
    return reach[x] ~= nil and reach[x][y] == true
end

-- Break room -------------------------------------------------------------

function World:placeBreakroom()
    local label, sizes = self:computeRegions()
    local bestId, bestSize = nil, 0
    for id, size in pairs(sizes) do
        if size > bestSize then bestId, bestSize = id, size end
    end
    local cx, cy = self.w / 2, self.h / 2
    local best, bestD = nil, math.huge
    if bestId then
        for x = 1, self.w - 1 do
            for y = 1, self.h - 1 do
                if label[x][y] == bestId and label[x + 1][y] == bestId
                    and label[x][y + 1] == bestId and label[x + 1][y + 1] == bestId then
                    local d = (x + 0.5 - cx) ^ 2 + (y + 0.5 - cy) ^ 2
                    if d < bestD then best, bestD = { x = x, y = y }, d end
                end
            end
        end
    end
    if not best then
        best = { x = math.floor(cx), y = math.floor(cy) }
    end
    self:setBreakroom(best.x, best.y)
end

function World:setBreakroom(x, y)
    self.breakroom = { x = x, y = y, tiles = {} }
    self.breakroom.cx = (x - 1) * TILE_SIZE + TILE_SIZE
    self.breakroom.cy = (y - 1) * TILE_SIZE + TILE_SIZE
    for dx = 0, 1 do
        for dy = 0, 1 do
            local t = self.tiles[x + dx][y + dy]
            t.type = TILE_BREAKROOM
            t.passable = true
            if t.node then self:removeNode(t.node) end
            table.insert(self.breakroom.tiles, { x = x + dx, y = y + dy })
        end
    end
    self.version = self.version + 1
    self.reachCache = nil
end

function World:nearestBreakroomTile(fromX, fromY)
    if not self.breakroom then return nil end
    local best, bestD = nil, math.huge
    for _, t in ipairs(self.breakroom.tiles) do
        local d = Util.manhattan(fromX, fromY, t.x, t.y)
        if d < bestD then best, bestD = t, d end
    end
    return best
end

function World:isBreakroomTile(x, y)
    local t = self:get(x, y)
    return t ~= nil and t.type == TILE_BREAKROOM
end

-- Passable tiles near the break room, closest first. Used to place new hires.
function World:spawnTiles(radius)
    radius = radius or 3
    local out = {}
    if not self.breakroom then return out end
    local reach = self:reachableFromBreakroom()
    local bx, by = self.breakroom.x, self.breakroom.y
    for x = bx - radius, bx + 1 + radius do
        for y = by - radius, by + 1 + radius do
            if self:inBounds(x, y) and reach[x][y] then
                out[#out + 1] = { x = x, y = y, d = Util.manhattan(x, y, bx, by) }
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

-- A random reachable tile nearby. Tiles with a stored item or break room
-- furniture are avoided so nobody idles on top of the pantry.
function World:randomNearbyPassable(rng, x, y, radius)
    local reach = self:reachableFromBreakroom()
    local fallback = nil
    for _ = 1, 12 do
        local nx = x + rng:int(-radius, radius)
        local ny = y + rng:int(-radius, radius)
        if (nx ~= x or ny ~= y) and self:inBounds(nx, ny) and reach[nx][ny] then
            local t = self.tiles[nx][ny]
            if not t.item and t.type ~= TILE_BREAKROOM then
                return { x = nx, y = ny }
            end
            fallback = fallback or { x = nx, y = ny }
        end
    end
    return fallback
end

-- Nearest free tile next to (x, y) to step off an item or the furniture.
function World:freeNeighbour(x, y)
    local reach = self:reachableFromBreakroom()
    for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 }, { x + 1, y + 1 }, { x - 1, y - 1 }, { x + 1, y - 1 }, { x - 1, y + 1 } }) do
        if self:inBounds(c[1], c[2]) and reach[c[1]][c[2]] then
            local t = self.tiles[c[1]][c[2]]
            if not t.item and t.type ~= TILE_BREAKROOM then return { x = c[1], y = c[2] } end
        end
    end
    return nil
end

-- Resource nodes ---------------------------------------------------------
-- bush: grows food on grass, ripens again after it is picked
-- tree: stands on grass, a lumberjack cuts it for logs, regrows from a stump
-- ore:  gold inside a stone tile, a miner works it from a neighbouring tile,
--       the tile turns to dirt when it is mined out

function World:addNode(kind, x, y)
    local node = {
        id = self.nextNodeId, kind = kind, x = x, y = y,
        ready = (kind ~= NODE_BUSH), timer = 0, claimedBy = nil, memo = false,
        fruit = self.rng and self.rng:int(1, 999) or 1,
    }
    if kind == NODE_BUSH then node.timer = BUSH_RIPEN_SECONDS end
    self.nextNodeId = self.nextNodeId + 1
    self.nodes[#self.nodes + 1] = node
    self.tiles[x][y].node = node
    return node
end

function World:removeNode(node)
    for i = #self.nodes, 1, -1 do
        if self.nodes[i] == node then table.remove(self.nodes, i) end
    end
    local t = self:get(node.x, node.y)
    if t and t.node == node then t.node = nil end
end

function World:nodesOfKind(kind)
    local out = {}
    for _, n in ipairs(self.nodes) do
        if n.kind == kind then out[#out + 1] = n end
    end
    return out
end

local function farFromOtherNodes(self, x, y)
    for _, node in ipairs(self.nodes) do
        if Util.manhattan(node.x, node.y, x, y) < NODE_MIN_SPACING then return false end
    end
    return true
end

-- The passable, reachable tile a morphi stands on to work this node.
-- Bushes and trees are worked in place; ore from a neighbouring tile.
function World:approachTile(node)
    if node.kind ~= NODE_ORE then
        if self:isReachable(node.x, node.y) then return { x = node.x, y = node.y } end
        return nil
    end
    local reach = self:reachableFromBreakroom()
    local candidates = { { node.x + 1, node.y }, { node.x - 1, node.y }, { node.x, node.y + 1 }, { node.x, node.y - 1 } }
    for _, c in ipairs(candidates) do
        if self:inBounds(c[1], c[2]) and reach[c[1]][c[2]] then
            return { x = c[1], y = c[2] }
        end
    end
    return nil
end

function World:nodeReachable(node)
    return self:approachTile(node) ~= nil
end

-- Plants up to `count` nodes of a kind. A share lands where the morphis
-- cannot reach yet, so the player always has something to dig toward.
function World:spawnNodes(kind, count, enclosedFraction)
    enclosedFraction = enclosedFraction or NODE_ENCLOSED_FRACTION
    local rng = self.rng
    local reach = self:reachableFromBreakroom()
    local reachable, enclosed = {}, {}
    for x = 1, self.w do
        for y = 1, self.h do
            local t = self.tiles[x][y]
            if not t.node then
                if kind == NODE_ORE then
                    if t.type == TILE_STONE then
                        local open = false
                        for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
                            if self:inBounds(c[1], c[2]) and reach[c[1]][c[2]] then open = true end
                        end
                        if open then reachable[#reachable + 1] = { x = x, y = y } else enclosed[#enclosed + 1] = { x = x, y = y } end
                    end
                elseif t.type == TILE_GRASS then
                    if reach[x][y] then reachable[#reachable + 1] = { x = x, y = y } else enclosed[#enclosed + 1] = { x = x, y = y } end
                end
            end
        end
    end
    local room = MAX_NODES_PER_KIND - #self:nodesOfKind(kind)
    if count > room then count = room end
    if count <= 0 then return {} end
    local wantEnclosed = math.floor(count * enclosedFraction + 0.5)
    if #enclosed == 0 then wantEnclosed = 0 end
    local wantReachable = count - wantEnclosed
    local planted = {}
    local function plantFrom(list, want)
        rng:shuffle(list)
        local i = 1
        while want > 0 and i <= #list do
            local p = list[i]
            if farFromOtherNodes(self, p.x, p.y) and not self.tiles[p.x][p.y].node then
                local node = self:addNode(kind, p.x, p.y)
                if kind == NODE_BUSH then
                    node.timer = rng:int(BUSH_FIRST_RIPEN_MIN, BUSH_FIRST_RIPEN_MAX)
                end
                planted[#planted + 1] = node
                want = want - 1
            end
            i = i + 1
        end
    end
    plantFrom(reachable, wantReachable)
    plantFrom(enclosed, wantEnclosed)
    return planted
end

function World:spawnAllNodes(counts)
    local planted = {}
    for _, kind in ipairs(NODE_KINDS) do
        for _, n in ipairs(self:spawnNodes(kind, counts[kind] or 0)) do planted[#planted + 1] = n end
    end
    return planted
end

-- Bushes ripen and stumps regrow. onReady(node) fires when a node becomes workable.
function World:update(dt, onReady)
    for _, node in ipairs(self.nodes) do
        if not node.ready then
            node.timer = node.timer - dt
            if node.timer <= 0 then
                node.ready = true
                if onReady then onReady(node) end
            end
        end
    end
end

-- A morphi finished working the node. Returns the cargo kind it yields.
function World:harvestNode(node)
    node.claimedBy = nil
    if node.kind == NODE_BUSH then
        node.ready = false
        node.timer = BUSH_RIPEN_SECONDS
        return CARGO_FOOD
    elseif node.kind == NODE_TREE then
        node.ready = false
        node.timer = TREE_REGROW_SECONDS
        return CARGO_LOGS
    else
        self:removeNode(node)
        node.ready = false
        self:setType(node.x, node.y, TILE_DIRT)
        return CARGO_GOLD
    end
end

function World:readyNodeCount(kind)
    local n = 0
    for _, node in ipairs(self.nodes) do
        if node.ready and (kind == nil or node.kind == kind) then n = n + 1 end
    end
    return n
end

-- Stockpile ------------------------------------------------------------
-- Logs and gold delivered to the break room. Building spends them.

function World:addStock(kind, n)
    self.stock[kind] = (self.stock[kind] or 0) + (n or 1)
end

function World:canAfford(cost)
    for kind, n in pairs(cost) do
        if (self.stock[kind] or 0) < n then return false end
    end
    return true
end

function World:spend(cost)
    if not self:canAfford(cost) then return false end
    for kind, n in pairs(cost) do
        self.stock[kind] = self.stock[kind] - n
    end
    return true
end

-- Storage --------------------------------------------------------------
-- Food is stored as an item on a built storage tile, one item per tile,
-- closest to the break room first. Without storage tiles food has nowhere
-- to go. Morphis walk over items freely; they just try not to idle on them.

function World:markStorage(x, y)
    local t = self:get(x, y)
    if not t or t.storage then return false end
    t.storage = true
    local d = 0
    if self.breakroom then
        d = (x - (self.breakroom.x + 0.5)) ^ 2 + (y - (self.breakroom.y + 0.5)) ^ 2
    end
    self.storageList[#self.storageList + 1] = { x = x, y = y, d = d }
    table.sort(self.storageList, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return true
end

function World:storageTiles()
    return self.storageList
end

function World:storageCapacity()
    return #self.storageList
end

-- Closest free storage tile to the break room. `reservedBy` lets a carrier
-- hold a tile so two foragers do not race for the same one.
function World:nearestFreeStorageTile(reservedBy)
    for _, s in ipairs(self.storageList) do
        local t = self.tiles[s.x][s.y]
        if t.passable and not t.item and (t.reservedBy == nil or t.reservedBy == reservedBy) then
            return { x = s.x, y = s.y }
        end
    end
    return nil
end

function World:reserveTile(x, y, worker)
    local t = self:get(x, y)
    if t then t.reservedBy = worker end
end

function World:releaseReservations(worker)
    for _, s in ipairs(self:storageTiles()) do
        local t = self.tiles[s.x][s.y]
        if t.reservedBy == worker then t.reservedBy = nil end
    end
end

function World:storeItem(kind, x, y, fruit)
    local t = self:get(x, y)
    if not t or t.item or not t.passable or not t.storage then return nil end
    local item = { id = self.nextItemId, kind = kind, x = x, y = y, fruit = fruit or 1, claimedBy = nil }
    self.nextItemId = self.nextItemId + 1
    self.items[#self.items + 1] = item
    t.item = item
    t.reservedBy = nil
    return item
end

function World:takeItem(x, y)
    local t = self:get(x, y)
    if not t or not t.item then return nil end
    local item = t.item
    t.item = nil
    for i = #self.items, 1, -1 do
        if self.items[i] == item then table.remove(self.items, i) end
    end
    item.claimedBy = nil
    return item
end

function World:storedCount(kind)
    local n = 0
    for _, item in ipairs(self.items) do
        if kind == nil or item.kind == kind then n = n + 1 end
    end
    return n
end

-- Nearest unclaimed stored item of a kind, by walking distance estimate.
function World:nearestStoredItem(kind, fromX, fromY)
    local best, bestD = nil, math.huge
    for _, item in ipairs(self.items) do
        if item.kind == kind and item.claimedBy == nil and self:isReachable(item.x, item.y) then
            local d = Util.manhattan(fromX, fromY, item.x, item.y)
            if d < bestD then best, bestD = item, d end
        end
    end
    return best
end

-- Designations ---------------------------------------------------------
-- The player marks tiles; morphis do the work. A mine site is stone or snow
-- a miner digs out when it can reach the tile next to it. A storage site
-- becomes a storage tile; a bridge site turns water into bridge. Any idle
-- morphi builds. Sites post jobs when placed and vanish when done.

-- A mine area is one drag's worth of marks. A miner claims the whole area
-- and works through it tile by tile, so it never idles between tiles.
function World:newArea()
    local area = { id = self.nextAreaId, sites = {}, claimedBy = nil }
    self.nextAreaId = self.nextAreaId + 1
    self.areas[#self.areas + 1] = area
    return area
end

function World:removeArea(area)
    area.claimedBy = nil
    for i = #self.areas, 1, -1 do
        if self.areas[i] == area then table.remove(self.areas, i) end
    end
end

function World:areaRemaining(area)
    return #area.sites
end

-- Any tile of the area a miner could stand next to right now.
function World:areaReachable(area)
    for _, site in ipairs(area.sites) do
        if self:siteApproachTile(site) then return true end
    end
    return false
end

-- The reachable site in the area closest to (x, y), with the tile to stand on.
function World:nextSiteInArea(area, x, y)
    local best, bestSpot, bestD = nil, nil, math.huge
    for _, site in ipairs(area.sites) do
        local spot = self:siteApproachTile(site)
        if spot then
            local d = Util.manhattan(x, y, spot.x, spot.y)
            if d < bestD then best, bestSpot, bestD = site, spot, d end
        end
    end
    return best, bestSpot
end

function World:addSite(kind, x, y, area)
    local t = self:get(x, y)
    if not t or t.site then return nil, 'already marked' end
    if kind == SITE_MINE then
        if t.type ~= TILE_STONE and t.type ~= TILE_SNOW then return nil, 'only stone and snow can be mined' end
    elseif kind == SITE_STORAGE then
        if not t.passable or t.type == TILE_BREAKROOM or t.item or t.node or t.storage then return nil, 'needs open ground' end
    elseif kind == SITE_BRIDGE then
        if t.type ~= TILE_WATER then return nil, 'bridges go over water' end
    end
    local site = { id = self.nextSiteId, kind = kind, x = x, y = y, claimedBy = nil, done = false, area = area }
    self.nextSiteId = self.nextSiteId + 1
    self.sites[#self.sites + 1] = site
    t.site = site
    if area then area.sites[#area.sites + 1] = site end
    return site
end

function World:removeSite(site)
    site.done = true
    site.claimedBy = nil
    for i = #self.sites, 1, -1 do
        if self.sites[i] == site then table.remove(self.sites, i) end
    end
    local t = self:get(site.x, site.y)
    if t and t.site == site then t.site = nil end
    local area = site.area
    if area then
        for i = #area.sites, 1, -1 do
            if area.sites[i] == site then table.remove(area.sites, i) end
        end
        if #area.sites == 0 then self:removeArea(area) end
    end
end

-- Where a morphi stands to work a site: on it for storage, next to it for
-- mine and bridge sites. nil while nothing reachable touches it.
function World:siteApproachTile(site)
    if site.kind == SITE_STORAGE then
        if self:isReachable(site.x, site.y) then return { x = site.x, y = site.y } end
        return nil
    end
    local reach = self:reachableFromBreakroom()
    for _, c in ipairs({ { site.x + 1, site.y }, { site.x - 1, site.y }, { site.x, site.y + 1 }, { site.x, site.y - 1 } }) do
        if self:inBounds(c[1], c[2]) and reach[c[1]][c[2]] then
            return { x = c[1], y = c[2] }
        end
    end
    return nil
end

function World:siteReachable(site)
    return self:siteApproachTile(site) ~= nil
end

-- Finish a site. Returns the cargo kind it yields, if any.
function World:completeSite(site)
    local t = self:get(site.x, site.y)
    local cargo = nil
    if site.kind == SITE_MINE then
        local node = t.node
        if node and node.kind == NODE_ORE then
            self:removeNode(node)
            node.ready = false
            cargo = CARGO_GOLD
        end
        self:setType(site.x, site.y, TILE_DIRT)
    elseif site.kind == SITE_STORAGE then
        self:markStorage(site.x, site.y)
    elseif site.kind == SITE_BRIDGE then
        self:setType(site.x, site.y, TILE_BRIDGE)
    end
    self:removeSite(site)
    return cargo
end

function World:sitesOfKind(kind)
    local out = {}
    for _, site in ipairs(self.sites) do
        if site.kind == kind then out[#out + 1] = site end
    end
    return out
end

function World:countTypes()
    local counts = {}
    for x = 1, self.w do
        for y = 1, self.h do
            local kind = self.tiles[x][y].type
            counts[kind] = (counts[kind] or 0) + 1
        end
    end
    return counts
end

return World
