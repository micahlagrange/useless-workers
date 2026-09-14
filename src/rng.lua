-- Deterministic Park-Miller generator. Pure Lua so tests and the game roll
-- the same numbers and so a shared seed makes the same map on every platform.
local Rng = {}
Rng.__index = Rng

local M = 2147483647
local A = 48271

function Rng.new(seed)
    local s = math.floor(math.abs(tonumber(seed) or 1)) % (M - 1) + 1
    return setmetatable({ state = s }, Rng)
end

-- Turn a seed string like "987" or "bananas" into a number.
function Rng.seedToNumber(seed)
    if type(seed) == 'number' then return math.floor(seed) end
    seed = tostring(seed or '')
    local asNumber = tonumber(seed)
    if asNumber then return math.floor(asNumber) end
    local n = 7
    for i = 1, #seed do
        n = (n * 31 + seed:byte(i)) % (M - 1)
    end
    return n
end

function Rng:random()
    self.state = (self.state * A) % M
    return (self.state - 1) / (M - 1)
end

-- Inclusive integer in [a, b]
function Rng:int(a, b)
    if b < a then a, b = b, a end
    local v = a + math.floor(self:random() * (b - a + 1))
    if v > b then v = b end
    return v
end

function Rng:pick(list)
    if #list == 0 then return nil end
    return list[self:int(1, #list)]
end

function Rng:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:int(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

return Rng
