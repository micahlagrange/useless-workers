local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local Jobs = require('src.jobs')
local Scoring = require('src.scoring')
local Worker = require('src.worker')
local Abilities = require('src.abilities')
local Campaign = require('src.campaign')

-- Plays a level with the real morphi AI after laying down a solution.
-- Returns the number of morphis who left, the points spent, and the lowest
-- hunger anyone hit.
local function play(index, solutionName)
    local run = Campaign.load(index, Rng.new(index))
    local world, def = run.world, run.def
    local jobs = Jobs.new()
    for _, node in ipairs(world.nodes) do
        if node.ready then jobs:postNode(node) end
    end
    local scoring = Scoring.new(2)
    local abilities = Abilities.new(world, jobs, function() end)
    local ok, why = Campaign.apply(def[solutionName], abilities)
    lu.assertTrue(ok, 'level ' .. index .. ' ' .. solutionName .. ': ' .. tostring(why))
    local workers = {}
    local quits = 0
    for i, spec in ipairs(run.specs) do
        workers[#workers + 1] = Worker.new(world, jobs, scoring, Rng.new(i), {
            x = spec.x, y = spec.y, role = spec.role, sheet = spec.sheet, name = spec.name,
            diet = spec.diet, hunger = spec.hunger, drain = def.drain,
            onEvent = function(_, name) if name == 'quit' then quits = quits + 1 end end,
        })
    end
    local clock, dt = 0, 1 / 30
    local lowest = HUNGER_MAX
    while clock < def.seconds do
        clock = clock + dt
        jobs:update(dt)
        world:update(dt, function(n) jobs:postNode(n) end)
        for _, w in ipairs(workers) do
            w:update(dt, clock)
            if w.alive and w.state ~= 'quitting' then lowest = math.min(lowest, w.hunger) end
        end
    end
    return quits, world.spent, lowest, workers
end

TestLevels = {}
function TestLevels:testEveryLevelIsWellFormed()
    lu.assertEquals(Campaign.count(), 5)
    local seen = {}
    for i = 1, Campaign.count() do
        local def = Campaign.levels[i]
        local ok, why = Campaign.validate(def)
        lu.assertTrue(ok, 'level ' .. i .. ': ' .. tostring(why))
        -- each level adds exactly one morphi
        lu.assertEquals(#def.morphis, i)
        for _, m in ipairs(def.morphis) do seen[m] = true end
        local run = Campaign.load(i, Rng.new(i))
        lu.assertEquals(#run.specs, i)
        lu.assertEquals(run.world.stock.logs, def.points)
        for _, spec in ipairs(run.specs) do
            lu.assertTrue(run.world:isReachable(spec.x, spec.y), 'spawn off the camp bank in level ' .. i)
        end
    end
    for _, species in ipairs({ 'pupper', 'woofoof', 'twins', 'cwab', 'blue' }) do
        lu.assertTrue(seen[species], species .. ' never shows up')
    end
end

function TestLevels:testFirstLevelIsPupperAndSteak()
    local def = Campaign.levels[1]
    lu.assertEquals(def.morphis, { 'pupper' })
    lu.assertEquals(MORPHI_DIET.pupper, 'steak')
    local run = Campaign.load(1, Rng.new(1))
    local steak = 0
    for _, n in ipairs(run.world.nodes) do
        if n.kind == NODE_BUSH then
            lu.assertEquals(n.food, 'steak')
            steak = steak + 1
        end
    end
    lu.assertTrue(steak >= 2)
end

function TestLevels:testStars()
    lu.assertEquals(Campaign.stars(1, { par = 1 }), 3)
    lu.assertEquals(Campaign.stars(0, { par = 1 }), 3)
    lu.assertEquals(Campaign.stars(3, { par = 1 }), 2)
    lu.assertEquals(Campaign.stars(4, { par = 1 }), 1)
end

function TestLevels:testObviousSolutionsWin()
    for i = 1, Campaign.count() do
        local quits, spent, lowest = play(i, 'obvious')
        print(string.format('  level %d obvious: spent %d, lowest hunger %d, quits %d', i, spent, math.floor(lowest), quits))
        lu.assertEquals(quits, 0, 'level ' .. i .. ': somebody left on the obvious solution')
        lu.assertTrue(spent <= Campaign.levels[i].points, 'level ' .. i .. ' obvious solution overspends')
    end
end

function TestLevels:testCleverSolutionsWinAtPar()
    for i = 1, Campaign.count() do
        local quits, spent, lowest = play(i, 'clever')
        print(string.format('  level %d clever:  spent %d, lowest hunger %d, quits %d', i, spent, math.floor(lowest), quits))
        lu.assertEquals(quits, 0, 'level ' .. i .. ': somebody left on the clever solution')
        lu.assertEquals(spent, Campaign.levels[i].par, 'level ' .. i .. ' clever solution is not at par')
    end
end

function TestLevels:testDoingNothingLosesTheFirstLevel()
    local run = Campaign.load(1, Rng.new(1))
    local jobs = Jobs.new()
    local scoring = Scoring.new(2)
    local quits = 0
    local spec = run.specs[1]
    local w = Worker.new(run.world, jobs, scoring, Rng.new(1), {
        x = spec.x, y = spec.y, role = spec.role, sheet = spec.sheet, diet = spec.diet, hunger = spec.hunger, drain = run.def.drain,
        onEvent = function(_, name) if name == 'quit' then quits = quits + 1 end end,
    })
    local clock, dt = 0, 1 / 30
    while clock < run.def.seconds do
        clock = clock + dt
        jobs:update(dt)
        run.world:update(dt, function(n) jobs:postNode(n) end)
        w:update(dt, clock)
    end
    lu.assertEquals(quits, 1, 'with no bridge Pupper should starve')
end

os.exit(lu.LuaUnit.run())
