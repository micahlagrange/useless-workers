local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Stats = require('src.stats')
love.load()
love.resize(1280, 720)

-- Plays free play for a while with no player at all.
local function play(seconds)
    H.newGame('PUPPER', 1)
    H.closeGoal()
    local game = H.game()
    local dt = 1 / 15
    for _ = 1, math.floor(seconds / dt) do
        love.update(dt)
        if H.state() == 'report' then love.keypressed('return') end
        if H.state() ~= 'playing' then break end
    end
    return game
end

TestStats = {}

function TestStats:test_a_row_and_a_map_for_every_day()
    local game = play(DAY_SECONDS * 4 + 1)
    local s = game.stats
    lu.assertEquals(#s.days, 5)
    lu.assertEquals(#s.maps, 5)
    lu.assertEquals(s.days[1].day, 1)
    lu.assertEquals(s.days[1].pop, DIFFICULTIES[1].workers)
    lu.assertEquals(s.days[1].season, 'Spring')
    lu.assertNotNil(s.maps[1].full)
    lu.assertEquals(#s.maps[1].full, game.world.h)
    lu.assertEquals(#s.maps[1].full[1], game.world.w)
end

function TestStats:test_the_map_on_a_day_is_rebuilt_from_changes()
    local game = play(DAY_SECONDS * 3 + 1)
    local s = game.stats
    -- dig a hole and let a day pass: that day's changes hold it
    local x, y
    for tx = 1, game.world.w do
        for ty = 1, game.world.h do
            if not x and game.world.tiles[tx][ty].type == TILE_STONE and not game.world.tiles[tx][ty].node then x, y = tx, ty end
        end
    end
    game.world:dig(x, y)
    local before = #s.days
    while #s.days == before do love.update(1 / 15) end
    local rows = s:mapOnDay(#s.days)
    lu.assertEquals(rows, Stats.mapRows(game.world))
    lu.assertEquals(rows[y]:sub(x, x), ',')
    lu.assertEquals(s:mapOnDay(1)[y]:sub(x, x), '#')
end

function TestStats:test_departures_and_arrivals_are_counted()
    local s = Stats.new({})
    local scoring = { quarter = 2, quarterTimer = QUARTER_SECONDS - DAY_SECONDS * 2 - 1 }
    s:event('arrived', { scoring = scoring, clock = 0 }, 'Dave')
    s:event('starved', { scoring = scoring, clock = 0 }, 'Priya')
    lu.assertEquals(s.counts.arrived, 1)
    lu.assertEquals(s.counts.starved, 1)
    lu.assertEquals(s.events[2].day, DAYS_PER_SEASON + 3)
end

function TestStats:test_milestones_wait_their_gap_and_the_biggest_wins()
    local s = Stats.new({})
    local base = { pop = 8, gold = 60, logs = 0, food = 0, quarter = 1, season = 'Spring' }
    local function row(day, extra)
        local r = { day = day }
        for k, v in pairs(base) do r[k] = v end
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end
    local m = s:checkMilestones(row(3))
    lu.assertEquals(m.id, 'band8') -- weighs more than fifty gold
    lu.assertNil(s:checkMilestones(row(4, { quarter = 5 })))
    local m2 = s:checkMilestones(row(3 + MILESTONE_GAP_DAYS, { quarter = 5 }))
    lu.assertEquals(m2.id, 'year1')
    lu.assertEquals(#s.milestones, 2)
end

function TestStats:test_export_is_json_with_the_blurb_cut_short()
    local game = play(DAY_SECONDS + 1)
    local out = game.stats:export(string.rep('x', 300))
    lu.assertStrContains(out, '"days":[')
    lu.assertStrContains(out, '"blurb":"' .. string.rep('x', STATS_BLURB_MAX) .. '"')
    lu.assertNotStrContains(out, string.rep('x', STATS_BLURB_MAX + 1))
    lu.assertEquals(Stats.json({ a = 'q"\n', b = { 1, 2 }, c = {} }), '{"a":"q\\"\\n","b":[1,2],"c":{}}')
end

function TestStats:test_history_reads_oldest_first()
    local s = Stats.new({})
    s.days[1] = { season = 'Spring' }
    s.days[2] = { season = 'Spring' }
    s:event('starved', { scoring = { quarter = 1, quarterTimer = QUARTER_SECONDS - DAY_SECONDS - 1 } }, 'Priya')
    s:event('arrived', { scoring = { quarter = 1, quarterTimer = QUARTER_SECONDS } }, 'Dave')
    local h = s:history()
    lu.assertEquals(h[1], 'Day 1 (Spring): Dave arrived.')
    lu.assertEquals(h[2], 'Day 2 (Spring): Priya starved and wandered off.')
end

function TestStats:test_an_arcade_level_counts_days_from_its_start()
    H.newLevel(1, 'arcade', 1)
    H.closeGoal()
    local game = H.game()
    for _ = 1, math.floor((DAY_SECONDS * 2 + 1) * 15) do
        love.update(1 / 15)
        if H.state() ~= 'playing' then break end
    end
    lu.assertTrue(#game.stats.days >= 1)
    lu.assertEquals(game.stats.days[1].day, 1)
end

function TestStats:test_the_note_takes_spaces_once()
    H.newGame('PUPPER', 1)
    H.openSub('export')
    H.sub.text = ''
    love.textinput('a')
    love.keypressed('space')
    love.textinput(' ')  -- the desktop sends the space as text too
    love.textinput('b')
    love.keypressed('space') -- love.js sends no text for it
    love.textinput('c')
    lu.assertEquals(H.sub.text, 'a b c')
    love.keypressed('escape')
end

function TestStats:test_run_names_sort_by_when_and_carry_the_note_and_build()
    lu.assertEquals(Stats.runName("idk but it was the first try so let's try it!", '20261019-182722', 107),
        '20261019-182722-idk-but-it-was-the-b107.json')
    lu.assertEquals(Stats.runName('', '20261020-090000', 123), '20261020-090000-run-b123.json')
    lu.assertEquals(Stats.runName('  !!  ', '20261020-090000', 123), '20261020-090000-run-b123.json')
end

function TestStats:test_export_shows_the_json_and_done_takes_it_away()
    H.newGame('PUPPER', 1)
    H.openSub('export')
    H.sub.text = 'bridges were fun'
    H.exportRun()
    lu.assertEquals(H.sub.saved.web, false)
    lu.assertStrContains(H.sub.saved.json, '"blurb":"bridges were fun"')
    lu.assertStrContains(H.sub.saved.json, '"runName":"' .. H.sub.saved.name .. '"')
    lu.assertStrContains(H.sub.saved.name, '-bridges-were-fun-b')
    love.keypressed('escape')
    lu.assertNil(H.sub.saved)
end

os.exit(lu.LuaUnit.run())
