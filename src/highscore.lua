-- Saved numbers: the high score per free play difficulty (by number) and
-- campaign progress (by name). Saved to disk everywhere; on the web love.js
-- keeps the save folder in IndexedDB and tools/patch_lovejs.py makes it flush.
local Highscore = {}
local memory = {}

-- Free play bests are kept as meadowN.highscore since the little blobs came
-- (eggs, nests, hunting and six jobs score differently); the old
-- difficultyN.highscore files stay on disk, unread. Campaign keys are as before.
local function fileName(key)
    if type(key) == 'number' then return 'meadow' .. key .. '.highscore' end
    return tostring(key) .. '.highscore'
end

local function canUseDisk()
    return love ~= nil and love.filesystem ~= nil
end

function Highscore.load(difficultyIndex)
    if memory[difficultyIndex] then return memory[difficultyIndex] end
    local value = 0
    -- love.js stalls on a read of a missing file, so look before reading
    local name = fileName(difficultyIndex)
    if canUseDisk() and love.filesystem.getInfo(name) then
        local ok, data = pcall(love.filesystem.read, name)
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
