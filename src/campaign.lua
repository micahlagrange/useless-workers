-- Loads a hand built level into a world and tells you how it went.
require('src.constants')
local Levels = require('src.levels')
local World = require('src.world')
local Rng = require('src.rng')

local Campaign = {}
Campaign.levels = Levels

function Campaign.count()
    return #Levels
end

-- Rows must be rectangular, the camp a 2x2 block, and every morphi's food
-- must grow somewhere.
function Campaign.validate(def)
    local w = #def.grid[1]
    for i, row in ipairs(def.grid) do
        if #row ~= w then return false, 'row ' .. i .. ' is ' .. #row .. ' wide, not ' .. w end
    end
    local camp = 0
    local foods = {}
    for _, row in ipairs(def.grid) do
        for i = 1, #row do
            local ch = row:sub(i, i)
            if ch == 'B' then camp = camp + 1 end
            if FOOD_CHAR[ch] then foods[FOOD_CHAR[ch]] = true end
        end
    end
    if camp ~= 4 then return false, 'camp must be a 2x2 block of B, found ' .. camp end
    for _, species in ipairs(def.morphis) do
        local diet = MORPHI_DIET[species]
        if not foods[diet] then return false, species .. ' eats ' .. diet .. ' and there is none' end
    end
    if def.par > def.points then return false, 'par is more than the starting points' end
    return true
end

-- Builds the world and lists the morphis to spawn. Returns a run table:
-- { def, index, world, specs = { {species, role, name, x, y, hunger} } }
function Campaign.load(index, rng)
    local def = Levels[index]
    if not def then return nil, 'no level ' .. tostring(index) end
    rng = rng or Rng.new(index)
    local world = World.fromGrid(def.grid, rng)
    world.stock = { logs = def.points, gold = 0 }
    world.spent = 0
    local spots = world:spawnTiles(2)
    local specs = {}
    for i, species in ipairs(def.morphis) do
        local spot = spots[(i - 1) % math.max(#spots, 1) + 1] or { x = world.breakroom.x, y = world.breakroom.y }
        specs[#specs + 1] = {
            species = species,
            role = MORPHI_ROLE[species],
            sheet = species,
            name = MORPHI_SHEET_NAMES[species],
            x = spot.x, y = spot.y,
            hunger = def.hunger,
            diet = MORPHI_DIET[species],
        }
    end
    return { def = def, index = index, world = world, specs = specs }
end

-- Three stars at par, two within a couple of points, one for surviving.
function Campaign.stars(spent, par)
    if spent <= par then return 3 end
    if spent <= par + 2 then return 2 end
    return 1
end

-- Lays a solution's designations down through an Abilities instance.
function Campaign.apply(solution, abilities)
    if not solution then return end
    for _, b in ipairs(solution.bridge or {}) do
        abilities:select(ABILITY_BRIDGE)
        local ok, why = abilities:useLine(b[1], b[2], b[3], b[4])
        if not ok then return false, 'bridge ' .. table.concat(b, ',') .. ': ' .. tostring(why) end
    end
    for _, f in ipairs(solution.floor or {}) do
        abilities:select(ABILITY_STORAGE)
        local ok, why = abilities:use(f[1], f[2])
        if not ok then return false, 'floor ' .. f[1] .. ',' .. f[2] .. ': ' .. tostring(why) end
    end
    for _, m in ipairs(solution.mine or {}) do
        abilities:select(ABILITY_MINE)
        local ok, why = abilities:designateMine(m[1], m[2], m[3], m[4])
        if not ok then return false, 'mine ' .. table.concat(m, ',') .. ': ' .. tostring(why) end
    end
    return true
end

return Campaign
