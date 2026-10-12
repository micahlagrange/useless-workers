-- Saved numbers: the high score per free play difficulty (by number) and
-- campaign progress (by name). Saved to disk everywhere; on the web love.js
-- keeps the save folder in IndexedDB and tools/patch_lovejs.py makes it flush.
local Highscore = {}
local memory = {}

local function fileName(key)
    if type(key) == 'number' then return 'difficulty' .. key .. '.highscore' end
    return tostring(key) .. '.highscore'
end

local function canUseDisk()
    return love ~= nil and love.filesystem ~= nil
end

function Highscore.load(difficultyIndex)
    if memory[difficultyIndex] then return memory[difficultyIndex] end
    local value = 0
    if canUseDisk() then
        local ok, data = pcall(love.filesystem.read, fileName(difficultyIndex))
        if ok and data then value = tonumber(data) or 0 end
    end
    memory[difficultyIndex] = value
    return value
end

-- Returns true when the score is a new record.
function Highscore.save(difficultyIndex, score)
    if score <= Highscore.load(difficultyIndex) then return false end
    memory[difficultyIndex] = score
    if canUseDisk() then
        pcall(love.filesystem.write, fileName(difficultyIndex), tostring(score))
    end
    return true
end

-- Store a value whatever it is (campaign progress, best points on a level).
function Highscore.set(key, value)
    memory[key] = value
    if canUseDisk() then
        pcall(love.filesystem.write, fileName(key), tostring(value))
    end
end

function Highscore.resetMemory()
    memory = {}
end

return Highscore
