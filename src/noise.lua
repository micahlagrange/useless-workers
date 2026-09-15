-- Seeded 2D value noise with a few octaves. Pure Lua and integer arithmetic
-- only, so the same seed draws the same map in the browser and on desktop.
-- Lattice values come from a seeded permutation table (the Perlin trick); the
-- earlier linear hash repeated in diagonal stripes across the whole map.
local Rng = require('src.rng')

local Noise = {}
Noise.__index = Noise

local function buildPermutation(seed)
    local rng = Rng.new(seed)
    local perm = {}
    for i = 0, 255 do perm[i] = i end
    for i = 255, 1, -1 do
        local j = rng:int(0, i)
        perm[i], perm[j] = perm[j], perm[i]
    end
    local out = {}
    for i = 0, 511 do out[i] = perm[i % 256] end
    return out
end

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

function Noise.new(seed, baseFrequency, octaves)
    local self = setmetatable({}, Noise)
    self.seed = math.floor(math.abs(seed or 1))
    self.baseFrequency = baseFrequency or (1 / 11)
    self.octaves = octaves or 3
    self.perms = {}
    for octave = 1, self.octaves do
        self.perms[octave] = buildPermutation(self.seed * 7 + octave * 1013)
    end
    return self
end

-- Value in [0, 1] at an integer lattice point.
function Noise:hash(perm, ix, iy)
    local x = ix % 256
    local y = iy % 256
    local a = perm[x + perm[y]]
    local b = perm[(x + 97) % 256 + perm[(y + 41) % 256]]
    return ((a * 256 + b) % 65536) / 65535
end

function Noise:lattice(perm, x, y)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    local sx, sy = smoothstep(fx), smoothstep(fy)
    local a = self:hash(perm, ix, iy)
    local b = self:hash(perm, ix + 1, iy)
    local c = self:hash(perm, ix, iy + 1)
    local d = self:hash(perm, ix + 1, iy + 1)
    local top = a + (b - a) * sx
    local bottom = c + (d - c) * sx
    return top + (bottom - top) * sy
end

-- Returns a value in [0, 1]
function Noise:value(x, y)
    local total, amplitude, frequency, norm = 0, 1, self.baseFrequency, 0
    for octave = 1, self.octaves do
        total = total + amplitude * self:lattice(self.perms[octave], x * frequency, y * frequency)
        norm = norm + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end
    return total / norm
end

return Noise
