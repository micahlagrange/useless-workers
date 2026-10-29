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

os.exit(lu.LuaUnit.run())
