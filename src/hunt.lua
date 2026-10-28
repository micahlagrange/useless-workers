-- Hunting parties. A band of hunters leaves the meadow and the screen
-- becomes one of the old arcade levels, now a hunting ground: its food
-- letters rest as critters and the level is won when they are all caught.
-- The party comes home with meat. Nothing here touches the colony: the
-- caller keeps the meadow aside while the party is away.
require('src.constants')
local Campaign = require('src.campaign')
local Rng = require('src.rng')

local Hunt = {}

HUNT_PARTY_SIZE   = 3   -- morphis in a party
HUNT_MEAT_PER_WEEK = 2  -- meat each hunter brings home per week away
HUNT_DAYS_PER_WEEK = 7
HUNT_LEAVE_DAY    = 8   -- day of the season the party sets out
HUNT_STORAGE_SPOTS = 14 -- floor spots set out by the camp for the catch
HUNT_BASKET_MEAT  = 4   -- meat a hunter's pouches hold before a basket is needed

-- Arcade levels hunters can clear alone: no river or rock between them
-- and the critters (checked in tst/hunt_test.lua).
Hunt.grounds = { 1, 6, 7 }

function Hunt.count()
    return #Hunt.grounds
end

-- Weeks a party is away: from the leave day to the end of the season.
function Hunt.weeksAway()
    return math.max(1, math.floor((DAYS_PER_SEASON - HUNT_LEAVE_DAY + 1 + HUNT_DAYS_PER_WEEK - 1) / HUNT_DAYS_PER_WEEK))
end

-- Meat the party brings home: each hunter, per week gone. Hunters carry
-- their catch in pouches; what does not fit needs a basket to unload into.
function Hunt.meatHome(partySize, weeks, baskets)
    local total = partySize * HUNT_MEAT_PER_WEEK * weeks
    if (baskets or 0) > 0 then return total, 0 end
    local cap = partySize * HUNT_BASKET_MEAT
    if total <= cap then return total, 0 end
    return cap, total - cap -- unloaded, left in the pouches
end

-- The party is hunters first, then anyone else, at most HUNT_PARTY_SIZE.
-- party = list of { name, sheet, species } picked by the player.
function Hunt.pick(candidates, chosen)
    local out = {}
    local taken = {}
    for _, name in ipairs(chosen or {}) do
        for _, c in ipairs(candidates) do
            if c.name == name and not taken[c] and #out < HUNT_PARTY_SIZE then taken[c] = true; out[#out + 1] = c end
        end
    end
    for pass = 1, 2 do
        for _, c in ipairs(candidates) do
            local isHunter = c.role == ROLE_HUNTER
            if not taken[c] and #out < HUNT_PARTY_SIZE and ((pass == 1) == isHunter) then taken[c] = true; out[#out + 1] = c end
        end
    end
    return out
end

-- Loads hunting ground `n` (an index into Hunt.grounds) for `party`.
-- Returns a run like Campaign.load's, with the food letters turned into
-- critters, and `critters` = how many there are to catch.
function Hunt.load(n, rng, party)
    local index = Hunt.grounds[n]
    if not index then return nil, 'no hunting ground ' .. tostring(n) end
    local run, why = Campaign.load(index, rng or Rng.new(index), 'arcade')
    if not run then return nil, why end
    local world = run.world
    world.arcade = false
    world.arcadeNeeds = nil
    world.hunting = true
    local bushes = {}
    for _, node in ipairs(world.nodes) do
        if node.kind == NODE_BUSH then bushes[#bushes + 1] = node end
    end
    for _, b in ipairs(bushes) do
        world:removeNode(b)
        world.tiles[b.x][b.y].node = nil
        local c = world:addNode(NODE_CRITTER, b.x, b.y)
        c.ready = true
    end
    -- meat needs somewhere to go: floor spots by the camp
    local br = world.breakroom or { x = 1, y = 1 }
    local placed = 0
    for r = 1, 8 do
        for dx = -r, r do
            for dy = -r, r do
                local t = world:get(br.x + dx, br.y + dy)
                if placed < HUNT_STORAGE_SPOTS and t and t.passable and not t.node and t.storage == 0 and world:isReachable(br.x + dx, br.y + dy) then
                    if world:markStorage(br.x + dx, br.y + dy) then placed = placed + 1 end
                end
            end
        end
    end
    run.critters = #bushes
    run.mode = 'hunt'
    run.saveKey = 'hunt'
    local spots = world:spawnTiles(2)
    run.specs = {}
    for i, p in ipairs(party or {}) do
        local spot = spots[(i - 1) % math.max(#spots, 1) + 1] or { x = world.breakroom.x, y = world.breakroom.y }
        run.specs[#run.specs + 1] = {
            species = p.species, role = ROLE_HUNTER, sheet = p.sheet, name = p.name,
            x = spot.x, y = spot.y, hunger = HUNGER_MAX, diet = p.diet,
        }
    end
    return run
end

-- Day of the season (1 to DAYS_PER_SEASON) for a scoring's quarter timer.
function Hunt.seasonDay(quarterTimer)
    local elapsed = QUARTER_SECONDS - quarterTimer
    return math.min(DAYS_PER_SEASON, math.floor(elapsed / DAY_SECONDS) + 1)
end

-- Puts `meat` pieces of steak into the meadow's storage, bins first
-- (storageList is already ordered that way). Returns how many fit.
function Hunt.deliver(world, meat)
    local stored = 0
    for _, s in ipairs(world.storageList) do
        while stored < meat and world:storeItem(ITEM_FOOD, s.x, s.y, MEAT) do stored = stored + 1 end
        if stored >= meat then break end
    end
    return stored
end

-- Critters still hopping about.
function Hunt.crittersLeft(world)
    return world:readyNodeCount(NODE_CRITTER)
end

function Hunt.won(world)
    return Hunt.crittersLeft(world) == 0
end

return Hunt
