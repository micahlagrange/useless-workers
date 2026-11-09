-- The little body effects: each starts, runs its length and stops; less
-- motion drops the movement but keeps the faces; the game triggers them and
-- draws 30 morphis with them without falling over.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Feel = require('src.feel')

local disk = {}
love.filesystem.write = function(name, data) disk[name] = data return true end
love.filesystem.read = function(name) return disk[name] end
love.filesystem.getInfo = function(name) return disk[name] and {} or nil end

love.load()

local function blob(t)
    t = t or {}
    t.id = t.id or 1
    t.animTime = t.animTime or 0
    t.speed = t.speed or WORKER_SPEED
    return t
end

TestFeel = {}

function TestFeel:setUp()
    disk = {}
    Feel.calm = false
end

function TestFeel:testBumpSquashesThenStops()
    local w = blob()
    Feel.start(w, 'bump', 10)
    local p = Feel.pose(w, 10)
    lu.assertTrue(p.sx > 1.1 and p.sy < 0.9, 'squashed wide at the start')
    local later = Feel.pose(w, 10 + Feel.BUMP_TIME + 0.01)
    lu.assertNil(Feel.age(w, 'bump', 10 + Feel.BUMP_TIME + 0.001, Feel.BUMP_TIME))
    lu.assertEquals(later.sx, 1)
end

function TestFeel:testHappyWigglesForItsLength()
    local w = blob({ moving = true })
    Feel.start(w, 'happy', 0)
    local wiggled = false
    for t = 0, Feel.HAPPY_TIME - 0.05, 0.05 do
        local p = Feel.pose(w, t)
        lu.assertTrue(p.happy)
        if math.abs(p.rot) > 0.05 then wiggled = true end
    end
    lu.assertTrue(wiggled)
    local after = Feel.pose(w, Feel.HAPPY_TIME + 0.01)
    lu.assertFalse(after.happy)
    lu.assertEquals(after.rot, 0)
end

function TestFeel:testWaveAndWalkHop()
    local w = blob({ moving = true, animTime = Feel.STEP_TIME / 2 })
    Feel.start(w, 'wave', 5)
    local p = Feel.pose(w, 5.3)
    lu.assertNotNil(p.wave)
    lu.assertTrue(p.hop > 1, 'up in the air mid-step')
    lu.assertTrue(p.shadow < 1, 'its shadow shrinks while up')
    lu.assertNil(Feel.pose(w, 5 + Feel.WAVE_TIME).wave)
    -- running hops higher
    local fast = blob({ moving = true, speed = WORKER_SPEED * 2, animTime = Feel.STEP_TIME * 0.35 })
    lu.assertTrue(Feel.pose(fast, 0).hop > p.hop)
end

function TestFeel:testFacesBlinkTalkAndNap()
    local w = blob()
    local blinks, open = 0, 0
    for t = 0, Feel.BLINK_EVERY * 3, 0.02 do
        if Feel.pose(w, t).blink then blinks = blinks + 1 else open = open + 1 end
    end
    lu.assertTrue(blinks > 0 and open > blinks * 10, 'blinks now and then')
    w.bubble = { text = 'hi', ttl = 1 }
    local saw = {}
    for t = 0, 1, 0.02 do saw[Feel.pose(w, t).mouthOpen] = true end
    lu.assertTrue(saw[true] and saw[false], 'mouth opens and shuts while it talks')
    w.bubble = nil
    w.state = 'breaking'
    local nap = Feel.pose(w, 1)
    lu.assertTrue(nap.eyesShut)
    lu.assertTrue(nap.sy < 1, 'lies a little flatter')
    lu.assertTrue(Feel.pose(blob(), 1, true).lookDown)
end

function TestFeel:testLessMotionKeepsFacesDropsMovement()
    Feel.setCalm(true)
    lu.assertEquals(disk[Feel.FILE], 'on')
    local w = blob({ moving = true, animTime = Feel.STEP_TIME / 2 })
    Feel.start(w, 'bump', 0)
    Feel.start(w, 'happy', 0)
    Feel.start(w, 'wave', 0)
    w.bubble = { text = 'hi', ttl = 1 }
    local p = Feel.pose(w, 0.05)
    lu.assertEquals(p.hop, 0)
    lu.assertEquals(p.sx, 1)
    lu.assertEquals(p.sy, 1)
    lu.assertEquals(p.rot, 0)
    lu.assertTrue(p.happy, 'happy face stays')
    lu.assertTrue(p.talking, 'mouth stays')
    lu.assertNotNil(p.wave, 'the arm is still up, just still')
    lu.assertEquals(Feel.pose(w, 0.4).wave, p.wave)
    Feel.calm = false
    Feel.load()
    lu.assertTrue(Feel.calm, 'remembered')
    Feel.setCalm(false)
end

function TestFeel:testGameTriggersAndDrawsThirty()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local game = H.game()
    for _ = 1, 30 do love.update(1 / 30) end
    local w = game.workers[1]
    w:feel('wave')
    lu.assertNotNil(Feel.age(w, 'wave', w.clock, Feel.WAVE_TIME))
    -- 30 morphis on screen, every effect at once, in both looks
    while #game.workers < 30 do
        local c = game.workers[(#game.workers % 4) + 1]
        local copy = setmetatable({}, getmetatable(c))
        for k, v in pairs(c) do copy[k] = v end
        copy.id = #game.workers + 1
        game.workers[#game.workers + 1] = copy
    end
    for i, m in ipairs(game.workers) do
        m:feel(({ 'bump', 'happy', 'wave' })[i % 3 + 1])
        if i % 4 == 0 then m.bubble = { text = 'hi', ttl = 1 } end
    end
    local t0 = os.clock()
    for _ = 1, 10 do love.draw() end
    love.keypressed('t')
    for _ = 1, 10 do love.draw() end
    love.keypressed('t')
    lu.assertTrue(os.clock() - t0 < 5, 'twenty frames of 30 morphis')
end

-- Count the drawing calls a function makes (the stub draws nothing).
local DRAWS = { 'draw', 'line', 'ellipse', 'rectangle', 'circle', 'polygon', 'print' }
local function countDraws(fn)
    local g, n, keep = love.graphics, 0, {}
    for _, k in ipairs(DRAWS) do
        keep[k] = rawget(g, k)
        local was = keep[k]
        rawset(g, k, function(...) n = n + 1; if was then return was(...) end end)
    end
    fn()
    for _, k in ipairs(DRAWS) do rawset(love.graphics, k, keep[k]) end
    return n
end

local Tileset = require('src.tileset')

local function eachLook(fn)
    local was = Tileset.current()
    for _, set in ipairs(Tileset.SETS) do
        Tileset.set(set)
        fn(set, Tileset.newView(H.game().world))
    end
    Tileset.set(was)
end

function TestFeel:testPickedStopsToLookThenGoesOn()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local game = H.game()
    local w
    for _ = 1, 600 do
        love.update(1 / 30)
        for _, m in ipairs(game.workers) do if m.alive and m.moving then w = m end end
        if w then break end
    end
    lu.assertNotNil(w, 'someone walks about')
    game.selectedWorker = w
    love.update(1 / 30)
    lu.assertTrue(Feel.looking(w, game.clock), 'picking it starts the look')
    local x, y, t0 = w.x, w.y, game.clock
    while game.clock - t0 < Feel.LOOK_TIME - 0.2 do
        love.update(1 / 30)
        lu.assertEquals(w.x, x)
        lu.assertEquals(w.y, y)
        lu.assertFalse(w.moving)
        lu.assertTrue(Feel.pose(w, game.clock, true).lookDown, 'eyes on you')
    end
    while game.clock - t0 < Feel.LOOK_TIME + 0.1 do love.update(1 / 30) end
    lu.assertFalse(Feel.looking(w, game.clock), 'then it gets on with things, still picked')
    -- picking the same one again later does not stop it again; picking anew does
    love.update(1 / 30)
    lu.assertFalse(Feel.looking(w, game.clock))
    game.selectedWorker = nil
    love.update(1 / 30)
    game.selectedWorker = w
    love.update(1 / 30)
    lu.assertTrue(Feel.looking(w, game.clock))
    game.selectedWorker = nil
end

function TestFeel:testEverySpeciesReadsApart()
    local ATLAS = require('src.kenney_atlas')
    local Rogue = require('src.view_rogue')
    local colours, n = {}, 0
    for sheet in pairs(MORPHI_SHEET_NAMES) do
        n = n + 1
        local c = MORPHI_COLOR[sheet]
        lu.assertNotNil(c, sheet .. ' has a colour')
        lu.assertNil(colours[c], sheet .. ' shares its colour with ' .. tostring(colours[c]))
        colours[c] = sheet
        for skin, rects in pairs(ATLAS) do
            if rects.pupper then lu.assertNotNil(rects[sheet], sheet .. ' has its own picture in ' .. skin) end
        end
        lu.assertNotNil(Rogue.SPECIES_GLYPH[sheet], sheet .. ' has a glyph')
    end
    lu.assertEquals(n, 6)
    for skin, rects in pairs(ATLAS) do
        if rects.pupper then
            local seen = {}
            for sheet in pairs(MORPHI_SHEET_NAMES) do
                local key = table.concat(rects[sheet], ',')
                lu.assertNil(seen[key], skin .. ': ' .. sheet .. ' and ' .. tostring(seen[key]) .. ' are one picture')
                seen[key] = sheet
            end
        end
    end
    -- the ring at its feet is drawn in its colour, in every look
    H.newGame('PUPPER', 1)
    local w = H.game().workers[1]
    local want = morphiColor(w.sheet)
    eachLook(function(set, view)
        local got = false
        local keep = rawget(love.graphics, 'setColor')
        rawset(love.graphics, 'setColor', function(r, g, b, a)
            if r == want[1] and g == want[2] and b == want[3] then got = true end
        end)
        view:drawWorker(w, 1, false)
        rawset(love.graphics, 'setColor', keep)
        lu.assertTrue(got, set .. ': the species ring')
    end)
end

function TestFeel:testCarryingShowsInEveryLook()
    H.newGame('PUPPER', 1)
    local w = H.game().workers[1]
    local loads = {
        sticks = { kind = CARGO_LOGS }, berries = { kind = CARGO_FOOD, food = 'grapes' },
        meat = { kind = CARGO_FOOD, food = 'steak' }, shinies = { kind = CARGO_GOLD },
        grass = { kind = CARGO_GRASS }, leaves = { kind = CARGO_LEAVES },
    }
    local keep = w.slots[SLOT_WORK]
    eachLook(function(set, view)
        w.slots[SLOT_WORK] = nil
        local empty = countDraws(function() view:drawWorkerCargo(w, 1, 1, w.y + 4) end)
        for what, cargo in pairs(loads) do
            w.slots[SLOT_WORK] = cargo
            local n = countDraws(function() view:drawWorkerCargo(w, 1, 1, w.y + 4) end)
            lu.assertTrue(n > empty, set .. ': ' .. what .. ' shows')
        end
    end)
    w.slots[SLOT_WORK] = keep
end

function TestFeel:testKenneyLooksMoveAndCalmDown()
    H.newGame('PUPPER', 1)
    local w = H.game().workers[1]
    local was = Tileset.current()
    for _, skin in ipairs({ 'pixel', 'soft' }) do
        Tileset.set(skin)
        local view = Tileset.newView(H.game().world)
        local rot, lifts = {}, {}
        local kr, kt = rawget(love.graphics, 'rotate'), rawget(love.graphics, 'translate')
        rawset(love.graphics, 'rotate', function(a) rot[#rot + 1] = a end)
        rawset(love.graphics, 'translate', function(x, y) lifts[#lifts + 1] = y; kt(x, y) end)
        w.moving, w.animTime = true, Feel.STEP_TIME / 2
        w.fx = nil
        w:feel('happy')
        w.pose = nil
        view:drawWorkerBody(w, w.clock + 0.05, 1, 100)
        lu.assertTrue(math.abs(rot[1] or 0) > 0.01, skin .. ': a happy wiggle')
        lu.assertTrue(lifts[1] < 100, skin .. ': a hop')
        Feel.calm = true
        rot, lifts = {}, {}
        view:drawWorkerBody(w, w.clock + 0.05, 1, 100)
        lu.assertEquals(rot[1], 0, skin .. ': no wiggle when calm')
        lu.assertEquals(lifts[1], 100, skin .. ': no hop when calm')
        Feel.calm = false
        -- a wave draws an arm
        w.fx = nil
        w:feel('wave')
        local still = countDraws(function() view:drawWorkerBody(w, w.clock + 5, 1, 100) end)
        local waving = countDraws(function() view:drawWorkerBody(w, w.clock + 0.1, 1, 100) end)
        lu.assertTrue(waving > still, skin .. ': waves')
        rawset(love.graphics, 'rotate', kr)
        rawset(love.graphics, 'translate', kt)
        w.moving, w.fx = false, nil
    end
    Tileset.set(was)
end

os.exit(lu.LuaUnit.run())
