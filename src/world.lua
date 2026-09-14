require('src.constants')
local Util = require('src.util')
local Noise = require('src.noise')

local World = {}
World.__index = World

local function newTile(kind, altitude)
    return { type = kind, altitude = altitude or 0.5, passable = PASSABLE[kind] or false, tree = nil, colorSeed = 0.5 }
end

function World.new(w, h, rng)
    local self = setmetatable({}, World)
    self.w, self.h = w or WORLD_W, h or WORLD_H
    self.rng = rng
    self.tiles = {}
    self.trees = {}
    self.nextTreeId = 1
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

-- Hand built worlds for tests. '.' grass  '#' stone  '~' water  'B' break room  'T' grass with a ripe tree
function World.fromGrid(rows, rng)
    local h = #rows
    local w = #rows[1]
    local self = World.new(w, h, rng)
    local breakroomTiles = {}
    local treeTiles = {}
    for y = 1, h do
        for x = 1, w do
            local ch = rows[y]:sub(x, x)
            local kind = TILE_GRASS
            if ch == '#' then kind = TILE_STONE
            elseif ch == '~' then kind = TILE_WATER
            elseif ch == 'B' then kind = TILE_BREAKROOM; breakroomTiles[#breakroomTiles + 1] = { x = x, y = y }
            elseif ch == 'T' then treeTiles[#treeTiles + 1] = { x = x, y = y }
            end
            local t = self.tiles[x][y]
            t.type = kind
            t.passable = PASSABLE[kind] or false
        end
    end
    if #breakroomTiles > 0 then
        local first = breakroomTiles[1]
        self.breakroom = { x = first.x, y = first.y, tiles = breakroomTiles }
        self.breakroom.cx = (first.x - 1) * TILE_SIZE + TILE_SIZE
        self.breakroom.cy = (first.y - 1) * TILE_SIZE + TILE_SIZE
    end
    for _, tt in ipairs(treeTiles) do
        local tree = self:addTree(tt.x, tt.y)
        tree.ripe = true
    end
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
    radius = radius or EXPLODE_RADIUS
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
            if t.tree then self:removeTree(t.tree) end
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

function World:randomNearbyPassable(rng, x, y, radius)
    local reach = self:reachableFromBreakroom()
    for _ = 1, 8 do
        local nx = x + rng:int(-radius, radius)
        local ny = y + rng:int(-radius, radius)
        if (nx ~= x or ny ~= y) and self:inBounds(nx, ny) and reach[nx][ny] then
            return { x = nx, y = ny }
        end
    end
    return nil
end

-- Trees ------------------------------------------------------------------

function World:addTree(x, y)
    local tree = {
        id = self.nextTreeId, x = x, y = y, ripe = false,
        timer = TREE_RIPEN_SECONDS, claimedBy = nil, memo = false,
        fruit = self.rng and self.rng:int(1, 999) or 1,
    }
    self.nextTreeId = self.nextTreeId + 1
    self.trees[#self.trees + 1] = tree
    self.tiles[x][y].tree = tree
    return tree
end

function World:removeTree(tree)
    for i = #self.trees, 1, -1 do
        if self.trees[i] == tree then table.remove(self.trees, i) end
    end
    local t = self:get(tree.x, tree.y)
    if t and t.tree == tree then t.tree = nil end
end

local function farFromOtherTrees(self, x, y)
    for _, tree in ipairs(self.trees) do
        if Util.manhattan(tree.x, tree.y, x, y) < TREE_MIN_SPACING then return false end
    end
    return true
end

-- Plants up to `count` trees on grass. A share of them lands in pockets the
-- workers cannot reach so the player always has something to fix.
function World:spawnTrees(count, enclosedFraction)
    enclosedFraction = enclosedFraction or TREE_ENCLOSED_FRACTION
    local rng = self.rng
    local reach = self:reachableFromBreakroom()
    local reachable, enclosed = {}, {}
    for x = 1, self.w do
        for y = 1, self.h do
            local t = self.tiles[x][y]
            if t.type == TILE_GRASS and not t.tree then
                if reach[x][y] then
                    reachable[#reachable + 1] = { x = x, y = y }
                else
                    enclosed[#enclosed + 1] = { x = x, y = y }
                end
            end
        end
    end
    local room = MAX_TREES - #self.trees
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
            if farFromOtherTrees(self, p.x, p.y) and not self.tiles[p.x][p.y].tree then
                local tree = self:addTree(p.x, p.y)
                tree.timer = rng:int(TREE_FIRST_RIPEN_MIN, TREE_FIRST_RIPEN_MAX)
                planted[#planted + 1] = tree
                want = want - 1
            end
            i = i + 1
        end
    end
    plantFrom(reachable, wantReachable)
    plantFrom(enclosed, wantEnclosed)
    return planted
end

function World:update(dt, onRipe)
    for _, tree in ipairs(self.trees) do
        if not tree.ripe then
            tree.timer = tree.timer - dt
            if tree.timer <= 0 then
                tree.ripe = true
                if onRipe then onRipe(tree) end
            end
        end
    end
end

function World:harvest(tree)
    tree.ripe = false
    tree.timer = TREE_RIPEN_SECONDS
    tree.claimedBy = nil
end

function World:ripeTreeCount()
    local n = 0
    for _, tree in ipairs(self.trees) do
        if tree.ripe then n = n + 1 end
    end
    return n
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
