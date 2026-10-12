-- Player tools. The player designates work and pays for building from the
-- stockpile; morphis do the actual digging and building.
require('src.constants')

local Abilities = {}
Abilities.__index = Abilities

-- onEffect(name, data) lets the view play sounds and toasts.
function Abilities.new(world, jobs, onEffect)
    local self = setmetatable({}, Abilities)
    self.world, self.jobs = world, jobs
    self.onEffect = onEffect
    self.selected = ABILITY_SELECT
    return self
end

function Abilities:effect(name, data)
    if self.onEffect then self.onEffect(name, data) end
end

function Abilities:select(tool)
    self.selected = tool
end

function Abilities:costText(tool)
    if tool == ABILITY_STORAGE then return self.world.arcade and 'free, living space' or 'free, 1 item' end
    if tool == ABILITY_BIN then return COSTS.bin.logs .. ' log, 4 items' end
    if tool == ABILITY_BED then return COSTS.bed.logs .. ' logs' end
    if tool == ABILITY_WALL then return COSTS.wall.logs .. ' log' end
    if tool == ABILITY_DOOR then return COSTS.door.logs .. ' log' end
    if tool == ABILITY_BRIDGE then return COSTS.bridge.logs .. ' log/tile' end
    if tool == ABILITY_MINE then return 'drag, free' end
    return 'free'
end

function Abilities:canAfford(tool)
    if tool == ABILITY_STORAGE then return self.world:canAfford(COSTS.storage) end
    if tool == ABILITY_BIN then return self.world:canAfford(COSTS.bin) end
    if tool == ABILITY_BED then return self.world:canAfford(COSTS.bed) end
    if tool == ABILITY_WALL then return self.world:canAfford(COSTS.wall) end
    if tool == ABILITY_DOOR then return self.world:canAfford(COSTS.door) end
    if tool == ABILITY_BRIDGE then return self.world:canAfford(COSTS.bridge) end
    return true
end

local function stoneOrSnow(t)
    return t and (t.type == TILE_STONE or t.type == TILE_SNOW)
end

local BUILD_KINDS = { [SITE_STORAGE] = true, [SITE_BIN] = true, [SITE_BED] = true, [SITE_BRIDGE] = true, [SITE_WALL] = true, [SITE_DOOR] = true }

-- Take a designation back. Logs come back unless someone has started on it.
function Abilities:cancelSite(site)
    local refund = not site.working
    self.jobs:removeSite(site)
    self.world:removeSite(site)
    if refund then self.world:refund(COSTS[site.kind] or {}) end
    self:effect('unmark', { count = 1, kind = site.kind })
    return true
end

-- Click tools. Returns true when something was placed, else false and a reason.
function Abilities:use(tx, ty)
    local tool = self.selected
    if SITE_FOR_TOOL[tool] then
        local kind = SITE_FOR_TOOL[tool]
        local cost = COSTS[kind]
        local t = self.world:get(tx, ty)
        if not t then return false, nil end
        -- clicking a designation with its own tool cancels it; with another
        -- build tool it becomes that kind instead
        if t.site and t.site.kind == kind then return self:cancelSite(t.site) end
        if t.site and BUILD_KINDS[t.site.kind] and t.site.kind ~= SITE_BRIDGE then
            if t.site.working then return false, 'Someone is already building that' end
            local refund = (COSTS[t.site.kind] or {}).logs or 0
            if self.world.stock.logs + refund < cost.logs then return false, 'Need ' .. cost.logs .. ' logs in the stockpile' end
            self:cancelSite(t.site)
        end
        if not self.world:canAfford(cost) then return false, 'Need ' .. cost.logs .. ' logs in the stockpile' end
        local site, why = self.world:addSite(kind, tx, ty)
        if not site then return false, why and (kind:sub(1, 1):upper() .. kind:sub(2) .. ' ' .. why) or nil end
        self.world:spend(cost)
        self.jobs:postSite(site)
        self:effect('site', { kind = kind, x = tx, y = ty })
        return true
    elseif tool == ABILITY_MINE then
        return self:designateMine(tx, ty, tx, ty)
    end
    return false, nil
end

-- Mine tool: a rectangle over stone. Dragging from an already marked tile
-- clears marks instead (only ones nobody has started on).
function Abilities:designateMine(x1, y1, x2, y2)
    local world = self.world
    local start = world:get(x1, y1)
    local clearing = start ~= nil and start.site ~= nil and start.site.kind == SITE_MINE
    local lx, hx = math.min(x1, x2), math.max(x1, x2)
    local ly, hy = math.min(y1, y2), math.max(y1, y2)
    local count = 0
    local area = nil
    for x = lx, hx do
        for y = ly, hy do
            local t = world:get(x, y)
            if clearing then
                if t and t.site and t.site.kind == SITE_MINE and not t.site.working then
                    world:removeSite(t.site)
                    count = count + 1
                end
            elseif stoneOrSnow(t) and not t.site and count < MINE_MAX_TILES then
                area = area or world:newArea()
                if world:addSite(SITE_MINE, x, y, area) then
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then
        return false, clearing and nil or 'Drag over stone to mark it for mining'
    end
    if area then self.jobs:postArea(area) end
    self:effect(clearing and 'unmark' or 'mine', { count = count, clearing = clearing })
    return true
end

-- Bridge tool: a drag from one tile to another marks every water tile on
-- the straight line as a bridge site. Costs logs per tile, all or nothing.
function Abilities:useLine(x1, y1, x2, y2)
    if x1 == x2 and y1 == y2 then
        local t = self.world:get(x1, y1)
        if t and t.site and t.site.kind == SITE_BRIDGE then return self:cancelSite(t.site) end
    end
    local tiles = self.world:lineTiles(x1, y1, x2, y2)
    local water = {}
    for _, p in ipairs(tiles) do
        local t = self.world:get(p.x, p.y)
        if t and t.type == TILE_WATER and not t.site then water[#water + 1] = p end
    end
    if #water == 0 then return false, 'Bridges only go over water' end
    local cost = { logs = #water * COSTS.bridge.logs }
    if not self.world:spend(cost) then return false, 'Need ' .. cost.logs .. ' logs for that bridge' end
    for _, p in ipairs(water) do
        local site = self.world:addSite(SITE_BRIDGE, p.x, p.y)
        if site then self.jobs:postSite(site) end
    end
    self:effect('site', { kind = SITE_BRIDGE, count = #water })
    return true
end

-- How each tool lays marks along a drag: a filled rectangle, a straight
-- line, or a single tile where the drag ends.
local DRAG_SHAPE = {
    [ABILITY_MINE] = 'rect', [ABILITY_STORAGE] = 'rect',
    [ABILITY_BRIDGE] = 'line', [ABILITY_WALL] = 'line',
}

local function siteKindFor(tool)
    if tool == ABILITY_MINE then return SITE_MINE end
    if tool == ABILITY_BRIDGE then return SITE_BRIDGE end
    return SITE_FOR_TOOL[tool]
end

local function rect(x1, y1, x2, y2)
    local tiles = {}
    for x = math.min(x1, x2), math.max(x1, x2) do
        for y = math.min(y1, y2), math.max(y1, y2) do tiles[#tiles + 1] = { x = x, y = y } end
    end
    return tiles
end

-- What a drag from (x1, y1) to (x2, y2) with the selected tool would touch.
-- A drag that starts on one of the tool's own marks clears that kind of
-- mark over the whole rectangle instead of laying new ones. Returns the
-- tiles and whether it clears.
function Abilities:dragPlan(x1, y1, x2, y2)
    local tool = self.selected
    local kind = siteKindFor(tool)
    if not kind then return {}, false end
    local start = self.world:get(x1, y1)
    if start and start.site and start.site.kind == kind then
        return rect(x1, y1, x2, y2), true
    end
    local shape = DRAG_SHAPE[tool]
    if shape == 'rect' then return rect(x1, y1, x2, y2), false end
    if shape == 'line' then return self.world:lineTiles(x1, y1, x2, y2), false end
    return { { x = x2, y = y2 } }, false
end

-- A press, a drag and a release with any tool but SELECT. Marks are laid
-- (or cleared) on release, never on the press.
function Abilities:useDrag(x1, y1, x2, y2)
    local tool = self.selected
    local kind = siteKindFor(tool)
    if not kind then return false, nil end
    local tiles, clearing = self:dragPlan(x1, y1, x2, y2)
    if tool == ABILITY_MINE then return self:designateMine(x1, y1, x2, y2) end
    if clearing then
        local count = 0
        for _, p in ipairs(tiles) do
            local t = self.world:get(p.x, p.y)
            if t and t.site and t.site.kind == kind and not t.site.working then
                self.jobs:removeSite(t.site)
                self.world:removeSite(t.site)
                self.world:refund(COSTS[kind] or {})
                count = count + 1
            end
        end
        if count == 0 then return false, 'Someone is already building that' end
        self:effect('unmark', { count = count, kind = kind })
        return true
    end
    if tool == ABILITY_BRIDGE then return self:useLine(x1, y1, x2, y2) end
    -- build tools: one mark per tile, skipping tiles that already have this
    -- kind, until the logs run out
    local placed, why = 0, nil
    for _, p in ipairs(tiles) do
        local t = self.world:get(p.x, p.y)
        if t and not (t.site and t.site.kind == kind) then
            local ok, reason = self:use(p.x, p.y)
            if ok then placed = placed + 1 else why = why or reason end
        end
    end
    if placed == 0 then return false, why end
    return true, (placed < #tiles and why) or nil
end

function Abilities:lineQuote(x1, y1, x2, y2)
    local tiles = self.world:lineTiles(x1, y1, x2, y2)
    local n = 0
    for _, p in ipairs(tiles) do
        local t = self.world:get(p.x, p.y)
        if t and t.type == TILE_WATER and not t.site then n = n + 1 end
    end
    return tiles, n * COSTS.bridge.logs
end

return Abilities
