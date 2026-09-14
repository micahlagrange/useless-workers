require('src.constants')

local Util = {}

function Util.tileToWorld(tx, ty)
    return { x = (tx - 1) * TILE_SIZE, y = (ty - 1) * TILE_SIZE }
end

function Util.tileCenter(tx, ty)
    return { x = (tx - 1) * TILE_SIZE + TILE_SIZE / 2, y = (ty - 1) * TILE_SIZE + TILE_SIZE / 2 }
end

function Util.worldToTile(px, py)
    return { x = math.floor(px / TILE_SIZE) + 1, y = math.floor(py / TILE_SIZE) + 1 }
end

function Util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Util.dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Util.manhattan(ax, ay, bx, by)
    return math.abs(ax - bx) + math.abs(ay - by)
end

function Util.hexToRgb(hex)
    hex = hex:gsub('#', '')
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
end

function Util.key(x, y)
    return x .. ':' .. y
end

function Util.round(v)
    return math.floor(v + 0.5)
end

function Util.formatTime(seconds)
    local s = math.max(0, math.ceil(seconds))
    return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

function Util.sign(v)
    if v > 0 then return 1 end
    if v < 0 then return -1 end
    return 0
end

return Util
