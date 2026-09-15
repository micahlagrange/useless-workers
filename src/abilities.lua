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
    if tool == ABILITY_STORAGE then return 'free, 1 item' end
    if tool == ABILITY_BIN then return COSTS.bin.logs .. ' log, 4 items' end
    if tool == ABILITY_BED then return COSTS.bed.logs .. ' logs' end
    if tool == ABILITY_BRIDGE then return COSTS.bridge.logs .. ' log/tile' end
    if tool == ABILITY_MEMO then return COSTS.memo.gold .. ' gold' end
    if tool == ABILITY_MINE then return 'drag, free' end
    return 'free'
end

function Abilities:canAfford(tool)
    if tool == ABILITY_STORAGE then return self.world:canAfford(COSTS.storage) end
    if tool == ABILITY_BIN then return self.world:canAfford(COSTS.bin) end
    if tool == ABILITY_BED then return self.world:canAfford(COSTS.bed) end
    if tool == ABILITY_BRIDGE then return self.world:canAfford(COSTS.bridge) end
    if tool == ABILITY_MEMO then return self.world:canAfford(COSTS.memo) end
    return true
end

local function stoneOrSnow(t)
    return t and (t.type == TILE_STONE or t.type == TILE_SNOW)
end

-- Click tools. Returns true when something was placed, else false and a reason.
function Abilities:use(tx, ty)
    local tool = self.selected
    if SITE_FOR_TOOL[tool] then
        local kind = SITE_FOR_TOOL[tool]
        local cost = COSTS[kind]
        local t = self.world:get(tx, ty)
        if not t then return false, nil end
        if not self.world:canAfford(cost) then return false, 'Need ' .. cost.logs .. ' logs in the stockpile' end
        local site, why = self.world:addSite(kind, tx, ty)
        if not site then return false, why and (kind:sub(1, 1):upper() .. kind:sub(2) .. ' ' .. why) or nil end
        self.world:spend(cost)
        self.jobs:postSite(site)
        self:effect('site', { kind = kind, x = tx, y = ty })
        return true
    elseif tool == ABILITY_MINE then
        return self:designateMine(tx, ty, tx, ty)
    elseif tool == ABILITY_MEMO then
        if not self.world:canAfford(COSTS.memo) then return false, 'Need ' .. COSTS.memo.gold .. ' gold for a memo' end
        local touched = 0
        for _, node in ipairs(self.world.nodes) do
            if math.abs(node.x - tx) <= MEMO_RADIUS and math.abs(node.y - ty) <= MEMO_RADIUS then
                node.memo = true
                if node.ready then self.jobs:postNode(node, true) end
                touched = touched + 1
            end
        end
        for _, site in ipairs(self.world.sites) do
            if math.abs(site.x - tx) <= MEMO_RADIUS and math.abs(site.y - ty) <= MEMO_RADIUS then
                self.jobs:prioritize(site.area or site)
                touched = touched + 1
            end
        end
        if touched == 0 then return false, 'Nothing to work on near that memo' end
        self.world:spend(COSTS.memo)
        self:effect('memo', { x = tx, y = ty, nodes = touched })
        return true
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
