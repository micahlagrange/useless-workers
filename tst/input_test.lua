-- Input that has to keep working on a phone.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()

TestInput = {}

function TestInput:setUp()
    Stub.width, Stub.height = 852, 393
    H.ui().touch = true
    love.resize(852, 393)
    H.newLevel(2, 'arcade', 1)
    H.closeGoal()
    Stub.fingers = {}
end

-- iOS can cancel a touch without a release. A pinch whose second finger
-- never says goodbye must not leave every later tap ignored.
function TestInput:testALostReleaseDoesNotFreezeTaps()
    Stub.fingers = { 'a', 'b' }
    love.touchpressed('a', 300, 200)
    love.touchpressed('b', 400, 200)
    love.touchreleased('a')
    -- 'b' is never released; LOVE just stops listing it
    Stub.fingers = {}
    love.update(1 / 30)
    local game = H.game()
    love.keypressed('3') -- FLOOR
    Stub.fingers = { 'c' }
    love.touchpressed('c', 300, 200)
    love.mousepressed(300, 200, 1, true)
    lu.assertNotNil(game.lineStart, 'the tap was ignored')
    love.mousereleased(300, 200, 1, true)
    love.touchreleased('c')
    lu.assertNil(game.lineStart)
end

-- A second finger turns a drag into a pinch: nothing gets built.
function TestInput:testAPinchCallsOffTheDrag()
    local game = H.game()
    love.keypressed('3')
    Stub.fingers = { 'a' }
    love.touchpressed('a', 300, 200)
    love.mousepressed(300, 200, 1, true)
    lu.assertNotNil(game.lineStart)
    Stub.fingers = { 'a', 'b' }
    love.touchpressed('b', 400, 200)
    lu.assertNil(game.lineStart)
    local before = #game.world.sites
    love.mousereleased(300, 200, 1, true)
    lu.assertEquals(#game.world.sites, before)
end

os.exit(lu.LuaUnit.run())
