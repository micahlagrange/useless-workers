-- Issue #34: a morphi's ring stayed glued to the morphi, so the buttons
-- slid away while it walked and were hard to press. The ring now stays
-- where it opened, and an open ring holds the camera still.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()

TestRingHoldsStill = {}

function TestRingHoldsStill:setUp()
    Stub.width, Stub.height = 1280, 720
    love.resize(1280, 720)
    H.newGame('ringstill', 1)
    H.closeGoal()
    H.setState('playing')
    self.game = H.game()
    self.game.paused = true -- only this test moves the morphi
    self.w = self.game.workers[1]
end

local function buttonsAt(hud, game)
    local out = {}
    for i, b in ipairs(hud:layout(game)) do out[i] = { x = b.x, y = b.y } end
    return out
end

function TestRingHoldsStill:testTheRingStaysWhereItOpenedWhileTheMorphiWalks()
    local hud, game, w = H.hud(), self.game, self.w
    game.follow = false
    H.openWorkerRing(w)
    lu.assertTrue(hud:isOpen(), 'no ring')
    local before = buttonsAt(hud, game)
    local ax, ay = hud:anchor(game)
    w.x, w.y = w.x + 40, w.y + 25
    love.update(1 / 60)
    local bx, by = hud:anchor(game)
    lu.assertAlmostEquals(bx, ax, 0.001)
    lu.assertAlmostEquals(by, ay, 0.001)
    lu.assertEquals(buttonsAt(hud, game), before)
    -- the spotlight still marks the morphi itself
    local shape = hud:pickShape(game)
    local p = game.camera:toScreen(w.x, w.y - 3)
    lu.assertAlmostEquals(shape.x, p.x / H.ui().scale, 0.001)
end

function TestRingHoldsStill:testFollowingWaitsWhileTheRingIsOpen()
    local hud, game, w = H.hud(), self.game, self.w
    H.openWorkerRing(w)
    game.selectedWorker, game.follow = w, true
    love.update(1 / 60)
    local before = buttonsAt(hud, game)
    local cx, cy = game.camera.x, game.camera.y
    w.x, w.y = w.x + 48, w.y + 32
    love.update(1 / 60)
    lu.assertEquals(game.camera.x, cx, 'the camera moved under an open ring')
    lu.assertEquals(game.camera.y, cy)
    lu.assertEquals(buttonsAt(hud, game), before)
    lu.assertTrue(game.follow, 'following was dropped')
    hud:close()
    love.update(1 / 60)
    lu.assertNotEquals(game.camera.x, cx, 'following did not carry on after the ring closed')
end

function TestRingHoldsStill:testANewRingOpensAtTheMorphisNewSpot()
    local hud, game, w = H.hud(), self.game, self.w
    game.follow = false
    H.openWorkerRing(w)
    hud:close()
    w.x, w.y = w.x + 30, w.y
    H.openWorkerRing(w)
    local ax, ay = hud:anchor(game)
    local p = game.camera:toScreen(w.x, w.y - 2)
    local s = H.ui().scale
    lu.assertAlmostEquals(ax, p.x / s, 0.001)
    lu.assertAlmostEquals(ay, p.y / s, 0.001)
end

os.exit(lu.LuaUnit.run())
