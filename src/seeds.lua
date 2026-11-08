-- The seed a new run starts with: one per kind of morphi, taken in turn, so
-- every new run of the game is a different meadow. The last one played is
-- remembered in the save directory; a seed the player types is left alone.
require('src.constants')

local Seeds = {}

Seeds.LIST = { 'PUPPER', 'WOOFOOF', 'TWINS', 'CWAB', 'BLOB', 'RIBBIT' }
Seeds.FILE = 'seed.txt'

local function indexOf(seed)
    for i, s in ipairs(Seeds.LIST) do if s == seed then return i end end
    return nil
end

-- One of ours (not one the player typed).
function Seeds.isOurs(seed) return indexOf(seed) ~= nil end

local function last()
    if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(Seeds.FILE)) then return nil end
    local ok, data = pcall(love.filesystem.read, Seeds.FILE)
    if not ok or type(data) ~= 'string' then return nil end
    return indexOf(data:match('%w+'))
end

-- The seed the next run starts with: the one after the last run's.
function Seeds.upcoming()
    local i = last() or 0
    return Seeds.LIST[i % #Seeds.LIST + 1]
end

-- A run started with this seed; one of ours moves the turn on.
function Seeds.played(seed)
    if not Seeds.isOurs(seed) then return end
    if love and love.filesystem and love.filesystem.write then
        pcall(love.filesystem.write, Seeds.FILE, seed)
    end
end

return Seeds
