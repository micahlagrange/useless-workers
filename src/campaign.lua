-- Loads a hand built level into a world and tells you how it went. Two
-- sets: 'arcade' (the default game, one meal each, no hunger) and
-- 'survival' (the retired campaign, keep everyone fed to the clock).
require('src.constants')
local Levels = require('src.levels')
local ArcadeLevels = require('src.arcade_levels')
local World = require('src.world')
local Rng = require('src.rng')

local Campaign = {}
Campaign.levels = Levels
Campaign.arcade = ArcadeLevels
Campaign.sets = { arcade = ArcadeLevels, survival = Levels }

-- Save keys per set: survival keeps the keys it always had.
Campaign.saveKey = { arcade = 'arcade', survival = 'level' }
Campaign.unlockKey = { arcade = 'arcade_unlocked', survival = 'levels_unlocked' }
Campaign.title = { arcade = 'ARCADE', survival = 'SURVIVAL' }

function Campaign.list(set)
    return Campaign.sets[set or 'survival']
end

function Campaign.count(set)
    return #Campaign.list(set)
end

-- Rows must be rectangular, the camp a 2x2 block, and every morphi's food
-- must grow somewhere (any food at all in arcade, where they eat anything).
function Campaign.validate(def, set)
    local w = #def.grid[1]
    for i, row in ipairs(def.grid) do
        if #row ~= w then return false, 'row ' .. i .. ' is ' .. #row .. ' wide, not ' .. w end
    end
    local camp = 0
    local foods = {}
    local anyFood = false
    for _, row in ipairs(def.grid) do
        for i = 1, #row do
            local ch = row:sub(i, i)
            if ch == 'B' then camp = camp + 1 end
            if FOOD_CHAR[ch] then foods[FOOD_CHAR[ch]] = true; anyFood = true end
        end
    end
    if camp ~= 4 then return false, 'camp must be a 2x2 block of B, found ' .. camp end
    if set == 'arcade' then
        if not anyFood then return false, 'nothing to eat' end
        for _, species in ipairs(def.morphis) do
            if not ARCADE_ROLE[species] then return false, species .. ' has no arcade role' end
        end
        for need in pairs(def.needs or {}) do
            local known = false
            for _, n in ipairs(ARCADE_NEED_ORDER) do if n == need then known = true end end
            if not known then return false, 'unknown need ' .. tostring(need) end
        end
    else
        for _, species in ipairs(def.morphis) do
            local diet = MORPHI_DIET[species]
            if not foods[diet] then return false, species .. ' eats ' .. diet .. ' and there is none' end
        end
    end
    if set == 'arcade' then
        for _, d in ipairs(ARCADE_DIFFICULTIES) do
            if type(def.points[d.key]) ~= 'number' then return false, 'no ' .. d.key .. ' points' end
        end
        local t = def.targets
        if type(t) ~= 'table' or type(t.easy) ~= 'number' or type(t.clever) ~= 'number' then return false, 'no targets' end
        if t.clever < 0 or t.clever > t.easy then return false, 'the clever target has to be between 0 and the easy target' end
        if t.easy > def.points.easy then return false, 'the easy target is more than the easy points' end
    elseif def.par > def.points then
        return false, 'par is more than the starting points'
    end
    return true
end

-- Logs a level starts with. Arcade budgets depend on the difficulty index.
function Campaign.points(def, set, difficulty)
    if set == 'arcade' then
        local d = ARCADE_DIFFICULTIES[difficulty or DEFAULT_ARCADE_DIFFICULTY] or ARCADE_DIFFICULTIES[DEFAULT_ARCADE_DIFFICULTY]
        return def.points[d.key]
    end
    return def.points
end

-- Builds the world and lists the morphis to spawn. Returns a run table:
-- { def, index, set, difficulty, points, world, specs = { {species, role, name, x, y, hunger} } }
function Campaign.load(index, rng, set, difficulty)
    set = set or 'survival'
    local def = Campaign.list(set)[index]
    if not def then return nil, 'no ' .. set .. ' level ' .. tostring(index) end
    rng = rng or Rng.new(index)
    local world = World.fromGrid(def.grid, rng)
    local points = Campaign.points(def, set, difficulty)
    world.stock = { logs = points, gold = 0 }
    world.spent = 0
    if set == 'arcade' then
        world.arcade = true
        world.arcadeNeeds = def.needs or {}
        world.arcadePopulation = #def.morphis
    end
    local spots = world:spawnTiles(2)
    local specs = {}
    for i, species in ipairs(def.morphis) do
        local spot = spots[(i - 1) % math.max(#spots, 1) + 1] or { x = world.breakroom.x, y = world.breakroom.y }
        specs[#specs + 1] = {
            species = species,
            role = set == 'arcade' and ARCADE_ROLE[species] or MORPHI_ROLE[species],
            sheet = species,
            name = MORPHI_SHEET_NAMES[species],
            x = spot.x, y = spot.y,
            hunger = set == 'arcade' and HUNGER_MAX or def.hunger,
            diet = MORPHI_DIET[species],
        }
    end
    return { def = def, index = index, set = set, difficulty = difficulty, points = points, world = world, specs = specs }
end

-- Arcade: three stars at or under the clever target, two at or under the
-- easy one, one for clearing. Survival: three at par, two within a couple.
function Campaign.stars(spent, def)
    if def.targets then
        if spent <= def.targets.clever then return 3 end
        if spent <= def.targets.easy then return 2 end
        return 1
    end
    if spent <= def.par then return 3 end
    if spent <= def.par + 2 then return 2 end
    return 1
end

-- Arcade: how many have had their meal.
function Campaign.ateCount(workers)
    local n = 0
    for _, w in ipairs(workers) do
        if w.alive and w.ate then n = n + 1 end
    end
    return n
end

function Campaign.allAte(workers)
    for _, w in ipairs(workers) do
        if w.alive and not w.ate then return false end
    end
    return #workers > 0
end

-- The arcade checklist, in the order the needs are checked, ending with
-- the meal count. Each entry is { label, done }.
function Campaign.goals(run, workers)
    local world, def = run.world, run.def
    local needs = def.needs or {}
    local pop = #def.morphis
    local out = {}
    if needs.bins then
        out[#out + 1] = { label = 'a BASKET to eat from', done = world:arcadeNeedMet('bins') }
    end
    if needs.floors then
        out[#out + 1] = { label = 'a STASH each (' .. math.min(#world.floors, pop) .. '/' .. pop .. ')', done = world:arcadeNeedMet('floors') }
    end
    if needs.enclosed then
        out[#out + 1] = { label = 'WALLS round the stashes, a DOOR', done = world:arcadeNeedMet('enclosed') }
    end
    if needs.binsInside then
        local bins = world:binCount()
        out[#out + 1] = { label = 'every BASKET inside (' .. world:binsInsideCount() .. '/' .. bins .. ')', done = world:arcadeNeedMet('binsInside') }
    end
    local ate = Campaign.ateCount(workers)
    out[#out + 1] = { label = 'everyone has eaten (' .. ate .. '/' .. pop .. ')', done = ate >= pop }
    return out
end

-- Lays a solution's designations down through an Abilities instance.
function Campaign.apply(solution, abilities)
    if not solution then return end
    local function place(tool, list, word)
        for _, f in ipairs(list or {}) do
            abilities:select(tool)
            local ok, why = abilities:use(f[1], f[2])
            if not ok then return false, word .. ' ' .. f[1] .. ',' .. f[2] .. ': ' .. tostring(why) end
        end
        return true
    end
    for _, b in ipairs(solution.bridge or {}) do
        abilities:select(ABILITY_BRIDGE)
        local ok, why = abilities:useLine(b[1], b[2], b[3], b[4])
        if not ok then return false, 'bridge ' .. table.concat(b, ',') .. ': ' .. tostring(why) end
    end
    local ok, why = place(ABILITY_STORAGE, solution.floor, 'floor')
    if not ok then return ok, why end
    ok, why = place(ABILITY_BIN, solution.bin, 'bin')
    if not ok then return ok, why end
    ok, why = place(ABILITY_WALL, solution.wall, 'wall')
    if not ok then return ok, why end
    ok, why = place(ABILITY_DOOR, solution.door, 'door')
    if not ok then return ok, why end
    for _, m in ipairs(solution.mine or {}) do
        abilities:select(ABILITY_MINE)
        ok, why = abilities:designateMine(m[1], m[2], m[3], m[4])
        if not ok then return false, 'mine ' .. table.concat(m, ',') .. ': ' .. tostring(why) end
    end
    return true
end

return Campaign
