-- High score per difficulty. Saved to disk on desktop, kept in memory on the
-- web build (love.js filesystem writes were unreliable in earlier jams).
local Highscore = {}
local memory = {}

local function fileName(difficultyIndex)
    return 'difficulty' .. difficultyIndex .. '.highscore'
end

local function canUseDisk()
    if not love or not love.filesystem then return false end
    if love.system and love.system.getOS() == 'Web' then return false end
    return true
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

function Highscore.resetMemory()
    memory = {}
end

return Highscore
