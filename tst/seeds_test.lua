-- A new run starts on the next morphi seed in turn, remembered between
-- launches; a seed the player typed is played as typed and left alone.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Seeds = require('src.seeds')

local disk = {}
love.filesystem.write = function(name, data) disk[name] = data return true end
love.filesystem.read = function(name) return disk[name] end
love.filesystem.getInfo = function(name) return disk[name] and {} or nil end

love.load()

local function startFree()
    H.goToTitle()
    for i, opt in ipairs(H.title.options) do
        if opt.kind == 'free' then H.title.option = i end
    end
    lu.assertEquals(H.title.options[H.title.option].kind, 'free')
    H.startFromTitle()
    return H.game().seedString
end

TestSeeds = {}

function TestSeeds:setUp() disk = {} end

function TestSeeds:testOneSeedPerMorphiKind()
    local n = 0
    for key, name in pairs(MORPHI_SHEET_NAMES) do
        n = n + 1
        lu.assertTrue(Seeds.isOurs(name:upper()), 'a seed for ' .. key)
    end
    lu.assertEquals(#Seeds.LIST, n)
end

function TestSeeds:testEachNewRunTakesTheNextSeed()
    H.title.seed = Seeds.upcoming()
    local played = {}
    for i = 1, #Seeds.LIST do
        played[i] = startFree()
        if i > 1 then lu.assertNotEquals(played[i], played[i - 1], 'run ' .. i .. ' is a new meadow') end
    end
    local seen = {}
    for _, s in ipairs(played) do seen[s] = true end
    for _, s in ipairs(Seeds.LIST) do lu.assertTrue(seen[s], s .. ' came up') end
    -- and round again
    lu.assertEquals(startFree(), played[1])
end

function TestSeeds:testTheTurnSurvivesALaunch()
    H.title.seed = Seeds.upcoming()
    local first = startFree()
    love.load()
    lu.assertNotEquals(H.title.seed, first, 'the next launch offers another seed')
    lu.assertEquals(first, Seeds.LIST[1])
    lu.assertEquals(startFree(), Seeds.LIST[2])
end

function TestSeeds:testATypedSeedIsLeftAlone()
    H.title.seed = Seeds.upcoming()
    startFree()
    local turn = disk[Seeds.FILE]
    H.title.seed = 'BANANAS'
    lu.assertEquals(startFree(), 'BANANAS')
    lu.assertEquals(H.title.seed, 'BANANAS')
    lu.assertEquals(disk[Seeds.FILE], turn)
end

function TestSeeds:testAnEmptySeedPlaysTheNextInTurn()
    H.title.seed = ''
    lu.assertEquals(startFree(), Seeds.LIST[1])
end

os.exit(lu.LuaUnit.run())
