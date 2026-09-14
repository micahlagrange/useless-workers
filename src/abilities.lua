require('src.constants')

local Abilities = {}
Abilities.__index = Abilities

-- onEffect(name, data) lets the view play sounds, shakes and explosions.
function Abilities.new(world, scoring, jobs, onEffect)
    local self = setmetatable({}, Abilities)
    self.world, self.scoring, self.jobs = world, scoring, jobs
    self.onEffect = onEffect
    self.selected = ABILITY_SELECT
    self.explodeRadius = EXPLODE_RADIUS
    self.lineCost = ABILITY_COST.line
    return self
end

function Abilities:effect(name, data)
    if self.onEffect then self.onEffect(name, data) end
end

function Abilities:select(tool)
    self.selected = tool
end

function Abilities:cost(tool)
    if tool == ABILITY_LINE then return self.lineCost end
    return ABILITY_COST[tool] or 0
end

function Abilities:canAfford(tool)
    return self.scoring:canAfford(self:cost(tool))
end

-- Click tools. Returns true when budget was spent, else false and a reason.
function Abilities:use(tx, ty)
    local tool = self.selected
    if tool == ABILITY_DIG then
        local t = self.world:get(tx, ty)
        if not t or t.type ~= TILE_STONE then return false, 'Dig only works on stone' end
        if not self.scoring:spend(self:cost(tool)) then return false, 'Not enough budget' end
        self.world:dig(tx, ty)
        self:effect('dig', { x = tx, y = ty })
        return true
    elseif tool == ABILITY_EXPLODE then
        if not self.scoring:canAfford(self:cost(tool)) then return false, 'Not enough budget' end
        local count = self.world:explode(tx, ty, self.explodeRadius)
        if count == 0 then return false, 'Nothing to blast here' end
        self.scoring:spend(self:cost(tool))
        self:effect('explode', { x = tx, y = ty, radius = self.explodeRadius })
        return true
    elseif tool == ABILITY_MEMO then
        if not self.scoring:canAfford(self:cost(tool)) then return false, 'Not enough budget' end
        local touched = 0
        for _, tree in ipairs(self.world.trees) do
            if math.abs(tree.x - tx) <= MEMO_RADIUS and math.abs(tree.y - ty) <= MEMO_RADIUS then
                tree.memo = true
                if tree.ripe then
                    self.jobs:postHarvest(tree, true)
                end
                touched = touched + 1
            end
        end
        if touched == 0 then return false, 'No trees near that memo' end
        self.scoring:spend(self:cost(tool))
        self:effect('memo', { x = tx, y = ty, trees = touched })
        return true
    end
    return false, nil
end

-- Bridge tool: a drag from one tile to another lays bridge over every water
-- tile on the straight line. Costs lineCost per water tile, all or nothing.
function Abilities:useLine(x1, y1, x2, y2)
    local tiles = self.world:lineTiles(x1, y1, x2, y2)
    local water = self.world:countType(tiles, TILE_WATER)
    if water == 0 then return false, 'Bridges only go over water' end
    local cost = water * self.lineCost
    if not self.scoring:spend(cost) then return false, 'Need ' .. cost .. ' budget for that bridge' end
    for _, p in ipairs(tiles) do
        self.world:bridge(p.x, p.y)
    end
    self:effect('line', { tiles = tiles, count = water })
    return true
end

function Abilities:lineQuote(x1, y1, x2, y2)
    local tiles = self.world:lineTiles(x1, y1, x2, y2)
    return tiles, self.world:countType(tiles, TILE_WATER) * self.lineCost
end

return Abilities
