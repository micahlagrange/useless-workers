-- Tamagotchi mode (epic tamagotchi): one baby on a screen of its own, FEED,
-- PLAY, CLEAN and NAP on the colony's real numbers, the meadow paused.
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
love.load()
love.resize(1280, 720)

local function baby(g)
    for _, w in ipairs(g.workers) do if w:isBaby() then return w end end
end

local function tap(ui, r)
    Stub.fingers = { 't' }
    love.touchpressed('t', (r.x + r.w / 2) * ui.scale, (r.y + r.h / 2) * ui.scale)
    love.touchreleased('t')
    Stub.fingers = {}
end

local function button(ui, id)
    for _, b in ipairs(ui.panelButtons) do if b.id == id then return b end end
end

TestTama = {}

function TestTama:setUp()
    H.newGame('PUPPER', 1)
    H.closeGoal()
    H.ui().touch = true
    love.resize(1280, 720)
    Stub.fingers = {}
    love.update(0)
end

function TestTama:tearDown()
    H.ui().touch = false
    love.resize(1280, 720)
    H.setState('playing')
end

function TestTama:test_tend_on_the_strip_opens_the_screen_and_the_meadow_stops()
    local g, ui = H.game(), H.ui()
    local b = baby(g)
    g.selectedWorker = b
    love.draw()
    lu.assertNotNil(ui.jobsButton, 'TEND on the baby strip')
    tap(ui, ui.jobsButton)
    lu.assertEquals(H.state(), 'tama')
    lu.assertTrue(g.tending == b)
    love.draw()
    for _, id in ipairs({ 'tama:feed', 'tama:play', 'tama:clean', 'tama:nap', 'tama:close' }) do
        lu.assertNotNil(button(ui, id), id)
    end
    -- the meadow is paused: nothing moves, nobody gets hungrier
    local clock, hunger, age = g.clock, g.workers[1].hunger, b.age
    for _ = 1, 50 do love.update(0.1) end
    lu.assertEquals(g.clock, clock)
    lu.assertEquals(g.workers[1].hunger, hunger)
    lu.assertEquals(b.age, age)
    -- MEADOW goes back
    tap(ui, button(ui, 'tama:close'))
    lu.assertEquals(H.state(), 'playing')
    love.update(0.1)
    lu.assertTrue(g.clock > clock, 'the meadow runs again')
end

function TestTama:test_the_buttons_use_the_colony_s_own_stock()
    local g = H.game()
    local b = baby(g)
    H.openTama(b)
    -- PLAY: more fun, a bit grubbier
    b.needs.fun, b.needs.clean = 20, 80
    H.pressTama('play')
    lu.assertTrue(b.needs.fun > 20)
    lu.assertTrue(b.needs.clean < 80)
    -- CLEAN needs a tuft of grass
    g.world.stock.grass = 0
    b.needs.clean = 10
    H.pressTama('clean')
    lu.assertEquals(b.needs.clean, 10, 'no grass, no wash')
    g.world.stock.grass = 2
    H.pressTama('clean')
    lu.assertTrue(b.needs.clean > 10)
    lu.assertEquals(g.world.stock.grass, 1)
    -- FEED takes a real stored meal it will eat
    local food = b.diet
    local spot
    for _, s in ipairs(g.world:storageTiles()) do spot = s break end
    if not spot then
        local br = g.world.breakroom
        g.world:markStorage(br.x + 3, br.y, 1)
        spot = { x = br.x + 3, y = br.y }
    end
    g.world:storeItem(ITEM_FOOD, spot.x, spot.y, food)
    b.hunger = 20
    local before = g.world:storedCount(ITEM_FOOD)
    H.pressTama('feed')
    lu.assertTrue(b.hunger > 20)
    lu.assertEquals(g.world:storedCount(ITEM_FOOD), before - 1)
    -- NAP tucks it in
    H.pressTama('nap')
    lu.assertTrue(b.tuckedIn)
end


function TestTama:test_it_says_what_each_action_does_and_costs()
    local g = H.game()
    local b = baby(g)
    H.openTama(b)
    g.world.stock.grass = 0
    local info = b:tendInfo('clean', g.world)
    lu.assertFalse(info.ok)
    lu.assertEquals(info.cost, '1 grass')
    lu.assertStrContains(info.have, 'no grass')
    H.pressTama('clean')
    lu.assertStrContains(g.tamaLast, 'no grass')
    g.world.stock.grass = 3
    info = b:tendInfo('clean', g.world)
    lu.assertTrue(info.ok)
    lu.assertStrContains(info.have, '3 grass')
    H.pressTama('clean')
    lu.assertStrContains(g.tamaLast, '2 grass left')
    local feed = b:tendInfo('feed', g.world)
    lu.assertEquals(feed.cost, '1 stored meal')
    lu.assertStrContains(b:tendInfo('play', g.world).cost, 'free')
    love.draw() -- the screen draws with all of it
end

os.exit(lu.LuaUnit.run())
