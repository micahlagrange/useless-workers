-- Which skin the world is drawn in. 'classic' is the painted tiles and
-- sprites; 'rogue' is a Dwarf Fortress look, one glyph per tile. The choice
-- is remembered in the save directory, like the volumes.
local Tileset = {}

Tileset.SETS = { 'classic', 'rogue' }
Tileset.LABELS = { classic = 'CLASSIC', rogue = 'ROGUE' }
Tileset.FILE = 'tileset.txt'

local current = Tileset.SETS[1]

local function known(name)
    for _, s in ipairs(Tileset.SETS) do if s == name then return true end end
    return false
end

function Tileset.current() return current end

function Tileset.label() return Tileset.LABELS[current] or current:upper() end

-- Choose a set; unknown names are ignored. Remembered when there is a disk.
function Tileset.set(name)
    if not known(name) then return false end
    current = name
    if love and love.filesystem and love.filesystem.write then
        pcall(love.filesystem.write, Tileset.FILE, current)
    end
    return true
end

function Tileset.cycle()
    for i, s in ipairs(Tileset.SETS) do
        if s == current then
            Tileset.set(Tileset.SETS[i % #Tileset.SETS + 1])
            return current
        end
    end
    Tileset.set(Tileset.SETS[1])
    return current
end

function Tileset.load()
    if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(Tileset.FILE)) then return end
    local ok, data = pcall(love.filesystem.read, Tileset.FILE)
    if not ok or type(data) ~= 'string' then return end
    local name = data:match('%a+')
    if name and known(name) then current = name end
end

-- The renderer for the current set: both draw with the same calls.
function Tileset.newView(world)
    if current == 'rogue' then
        return require('src.view_rogue').new(world)
    end
    return require('src.view').new(world)
end

return Tileset
