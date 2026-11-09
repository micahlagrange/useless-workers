-- The meadow voice (CLAUDE.md, Voice): no player-facing string uses the old
-- frontier words. Scans the string tables, then plays free play for a season
-- and a half and reads everything drawn on screen, the log and the history.
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Stats = require('src.stats')
local Worker = require('src.worker')
love.load()
love.resize(1280, 720)

local BANNED = {
    'dwarf', 'wilds', 'settler', 'migrant', 'lumber', 'chop', 'chopping', 'fell', 'felled', 'log', 'logs',
    'stone', 'gold', 'ore', 'mine', 'mines', 'mining', 'miner', 'camp', 'hardship', 'hardships', 'quit', 'band',
}

-- the banned words in a text, as whole words, any case
local function banned(text)
    local found = {}
    local lower = tostring(text):lower()
    for _, w in ipairs(BANNED) do
        if lower:find('%f[%a]' .. w .. '%f[%A]') then found[#found + 1] = w end
    end
    return found
end

-- the LOG button opens the announcements: that log is a fine word
local ALLOWED = { LOG = true }

local function check(where, text, problems)
    if ALLOWED[text] then return end
    local f = banned(text)
    if #f > 0 then problems[#problems + 1] = where .. ': "' .. text .. '" (' .. table.concat(f, ', ') .. ')' end
end

TestWords = {}

function TestWords:test_the_string_tables_use_meadow_words()
    local problems = {}
    for key, r in pairs(ROLES) do
        check('ROLES.' .. key .. '.label', r.label, problems)
        check('ROLES.' .. key .. '.verb', r.verb, problems)
    end
    for key, l in pairs(ABILITY_LABEL) do check('ABILITY_LABEL.' .. key, l, problems) end
    for i, d in ipairs(DIFFICULTIES) do check('DIFFICULTIES[' .. i .. ']', d.name, problems) end
    for _, m in ipairs(Stats.MILESTONES) do check('milestone ' .. m.id, m.text, problems) end
    for _, why in ipairs({ 'storage', 'water', 'walled', 'taken', 'none' }) do
        for _, job in ipairs({ ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER, ROLE_BUILDER }) do
            check('idle ' .. job .. ' ' .. why, Worker.idleText({ { job = job, slot = 'main', why = why } }, true, job), problems)
        end
    end
    lu.assertEquals(problems, {})
end

function TestWords:test_a_season_of_free_play_reads_in_meadow_words()
    local problems, seen = {}, {}
    local function scan(where, text)
        if text and not seen[text] then
            seen[text] = true
            check(where, text, problems)
        end
    end
    Stub.texts = {}
    -- the title, on each option
    H.goToTitle()
    H.buildTitleOptions()
    for i = 1, #H.title.options do
        H.title.option = i
        love.draw()
    end
    H.newGame('PUPPER', 1)
    local g = H.game()
    love.draw() -- the goal screen
    H.closeGoal()
    local dt = 0.1
    for step = 1, math.floor(QUARTER_SECONDS * 1.5 / dt) do
        love.update(dt)
        local st = H.state()
        if st == 'report' then
            love.draw()
            love.keypressed('return')
        elseif st == 'huntpick' then
            love.draw() -- the hunters are asked for; the meadow stays home
            love.keypressed('escape')
        elseif st ~= 'playing' then
            break
        end
        if step % 50 == 0 then
            g.selectedWorker = g.workers[(step / 50) % #g.workers + 1]
            for _, w in ipairs(g.workers) do scan('describeState', w:describeState()) end
            love.draw()
        end
    end
    for _, t in ipairs(Stub.texts or {}) do scan('drawn', t.text) end
    for _, e in ipairs(g.log) do scan('log', e.text) end
    for _, line in ipairs(g.stats:history()) do scan('history', line) end
    lu.assertTrue(#g.log > 0, 'the season wrote something to the log')
    lu.assertTrue(g.clock >= QUARTER_SECONDS, 'played past the first season, got to ' .. g.clock)
    lu.assertEquals(problems, {})
end

os.exit(lu.LuaUnit.run())
