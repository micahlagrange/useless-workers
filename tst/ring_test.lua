-- The radial tool's rings (epic-toybox-radial-ui): a tap on each kind of
-- square offers the right buttons, dig patch takes the connected clay, and
-- painting marks exact squares.
local lu = require('libs.luaunit')
require('src.constants')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Abilities = require('src.abilities')
local Ring = require('src.ring')

local GRID = {
    '..........',
    '.BB..T..##',
    '.BB.b..###',
    '........#.',
    '.S..N.~~..',
    '..d...~~..',
}

local function setup(free)
    local world = World.fromGrid(GRID, Rng.new(1))
    world.wilds = free or false
    world.stock = { logs = 10, grass = 10, leaves = 10, gold = 0 }
    local jobs = Jobs.new(world)
    return world, Abilities.new(world, jobs)
end

local function ids(spec)
    local out = {}
    for _, it in ipairs(spec.items) do out[#out + 1] = it.id end
    return table.concat(out, ' ')
end

TestRing = {}

function TestRing:test_open_grass_offers_what_the_mode_builds()
    local world = setup(true)
    local spec = Ring.forTile(world, 4, 4, TOOLS_SURVIVAL)
    lu.assertEquals(spec.kind, 'grass')
    lu.assertEquals(ids(spec), 'build:storage build:bin build:bed')
    spec = Ring.forTile(world, 4, 4, TOOLS_ARCADE)
    lu.assertEquals(ids(spec), 'build:storage build:bin build:wall build:door')
    lu.assertEquals(spec.tile.x, 4)
end

function TestRing:test_what_you_cannot_afford_says_what_is_missing()
    local world = setup(true)
    world.stock = { logs = 0, grass = 0, leaves = 0, gold = 0 }
    local spec = Ring.forTile(world, 4, 4, TOOLS_SURVIVAL)
    local stash, nest = spec.items[1], spec.items[3]
    lu.assertNil(stash.off, 'a stash is free')
    lu.assertTrue(nest.off)
    lu.assertStrContains(nest.cost, 'needs')
end

function TestRing:test_clay_water_home_and_things()
    local world = setup(true)
    lu.assertEquals(ids(Ring.forTile(world, 9, 2, TOOLS_SURVIVAL)), 'dig digpatch')
    lu.assertEquals(ids(Ring.forTile(world, 7, 5, TOOLS_SURVIVAL)), 'bridge')
    local home = Ring.forTile(world, 2, 3, TOOLS_SURVIVAL)
    lu.assertEquals(home.kind, 'home')
    lu.assertEquals(home.tile.w, 2)
    -- a bush and a tree only have something to say
    local spec, caption = Ring.forTile(world, 5, 3, TOOLS_SURVIVAL)
    lu.assertNil(spec)
    lu.assertStrContains(caption.title, 'bush')
    spec, caption = Ring.forTile(world, 6, 2, TOOLS_SURVIVAL)
    lu.assertNil(spec)
    lu.assertStrContains(caption.title, 'tree')
    -- a stash, a basket (either of its two squares) and a nest can be taken away
    lu.assertEquals(ids(Ring.forTile(world, 2, 5, TOOLS_SURVIVAL)), 'takeaway')
    local basket = Ring.forTile(world, 6, 5, TOOLS_SURVIVAL)
    lu.assertEquals(ids(basket), 'takeaway')
    lu.assertEquals(basket.tile.x, 5)
    lu.assertEquals(basket.tile.w, 2)
    lu.assertEquals(ids(Ring.forTile(world, 3, 6, TOOLS_SURVIVAL)), 'takeaway')
end

function TestRing:test_dig_patch_takes_the_connected_clay()
    local world, abilities = setup(true)
    local patch = Ring.patch(world, 9, 2)
    lu.assertEquals(#patch, 6)
    lu.assertEquals(abilities:markTiles(patch), 6)
    local spec = Ring.forTile(world, 9, 2, TOOLS_SURVIVAL)
    lu.assertEquals(ids(spec), 'unmark unmarkall')
    lu.assertEquals(abilities:unmarkTiles({ { x = 9, y = 2 } }), 1)
    -- nobody's working it, so the rest wipe too
    lu.assertEquals(abilities:unmarkTiles(Ring.patch(world, 9, 3, 100, function(t) return t.site and t.site.kind == SITE_MINE end)), 5)
end

function TestRing:test_a_bridge_is_laid_a_square_at_a_time_while_sticks_last()
    local world, abilities = setup(true)
    world.stock.logs = 1
    local cost = costOf(world, 'bridge').logs or 0
    local laid, why = abilities:bridgeTiles({ { x = 7, y = 5 }, { x = 8, y = 5 } })
    if cost == 1 then
        lu.assertEquals(laid, 1)
        lu.assertStrContains(why, 'Out of sticks')
    end
    lu.assertNotNil(world:get(7, 5).site)
    local spec = Ring.forTile(world, 7, 5, TOOLS_SURVIVAL)
    lu.assertEquals(ids(spec), 'calloff')
end

function TestRing:test_take_away_refuses_a_stash_holding_food()
    local world, abilities = setup(true)
    world:storeItem(ITEM_FOOD, 2, 5, 'berries')
    local ok, why = abilities:takeAway(2, 5)
    lu.assertFalse(ok)
    lu.assertStrContains(why, 'holding food')
    lu.assertTrue(abilities:takeAway(5, 5), 'an empty basket goes')
    lu.assertEquals(world:get(5, 5).storage, 0)
    lu.assertNil(world:get(6, 5).binPart)
    lu.assertTrue(abilities:takeAway(3, 6), 'a nest goes')
    lu.assertFalse(world:get(3, 6).bed)
end

function TestRing:test_ring_offsets_keep_buttons_apart()
    for n = 1, 12 do
        local offs = Ring.offsets(n, 56)
        for i = 1, n do
            for j = i + 1, n do
                local d = math.sqrt((offs[i].x - offs[j].x) ^ 2 + (offs[i].y - offs[j].y) ^ 2)
                lu.assertTrue(d >= 56, n .. ' buttons: ' .. i .. ' and ' .. j .. ' overlap')
            end
        end
    end
end

os.exit(lu.LuaUnit.run())
