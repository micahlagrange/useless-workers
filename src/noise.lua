-- Seeded 2D value noise with a few octaves. Pure Lua and integer arithmetic
-- only, so the same seed draws the same map in the browser and on desktop.
local Noise = {}
Noise.__index = Noise

local M = 2147483647

local function hash(ix, iy, seed)
    local n = (ix * 1619 + iy * 31337 + seed * 6971) % M
    n = (n * 48271) % M
    n = (n * 48271) % M
    return n / M
end

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

local function lattice(x, y, seed)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    local sx, sy = smoothstep(fx), smoothstep(fy)
    local a = hash(ix, iy, seed)
    local b = hash(ix + 1, iy, seed)
    local c = hash(ix, iy + 1, seed)
    local d = hash(ix + 1, iy + 1, seed)
    local top = a + (b - a) * sx
    local bottom = c + (d - c) * sx
    return top + (bottom - top) * sy
end

function Noise.new(seed, baseFrequency, octaves)
    local self = setmetatable({}, Noise)
    self.seed = math.floor(math.abs(seed or 1)) % 100000 + 1
    self.baseFrequency = baseFrequency or (1 / 11)
    self.octaves = octaves or 3
    return self
end

-- Returns a value in [0, 1]
function Noise:value(x, y)
    local total, amplitude, frequency, norm = 0, 1, self.baseFrequency, 0
    for octave = 1, self.octaves do
        total = total + amplitude * lattice(x * frequency + octave * 17.3, y * frequency + octave * 9.1, self.seed + octave * 101)
        norm = norm + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end
    return total / norm
end

return Noise
