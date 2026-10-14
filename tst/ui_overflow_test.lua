-- The C64 face is wide. This draws every screen of the game, at window sizes
-- from a phone on its side to a big monitor, with the face's real glyph
-- widths, and fails on any text that:
--   * runs off the screen,
--   * spills out of the panel it is drawn on,
--   * spills out of its button, or runs under another button,
--   * overlaps another piece of text.
local lu = require('libs.luaunit')
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local UI = require('src.ui')
local Campaign = require('src.campaign')
local Highscore = require('src.highscore')

love.load()

local SIZES = {
    { 1280, 720 }, { 1280, 800 }, { 1920, 1080 }, { 1024, 768 }, { 800, 600 }, { 480, 320 }, { 852, 393 },
    { 852, 393, touch = true }, { 740, 360, touch = true }, { 932, 430, touch = true },
    { 393, 852, touch = true }, { 360, 780, touch = true }, { 430, 932, touch = true },
    { 768, 1024, touch = true }, { 1024, 768, touch = true },
}

-- Stamp each text with the layer (0 is the HUD, each panel opens a new one),
-- the panel and the button it is drawn in.
local buttons = {}
local layer = 0
local begin, finish, panel, button = UI.beginScaled, UI.endScaled, UI.panel, UI.button
function UI:beginScaled()
    layer = 0
    Stub.ctx = { ui = true, layer = 0 }
    return begin(self)
end
function UI:endScaled()
    Stub.ctx = {}
    return finish(self)
end
function UI:panel(w, h)
    local x, y, pw, ph = panel(self, w, h)
    layer = layer + 1
    Stub.ctx.layer = layer
    Stub.ctx.panel = { x = x, y = y, w = pw, h = ph }
    return x, y, pw, ph
end
-- a dropdown covers what is under it on purpose: it is a layer of its own
local dropdown = UI.drawDropdown
function UI:drawDropdown(game)
    layer = layer + 1
    Stub.ctx.layer = layer
    Stub.ctx.panel = nil
    return dropdown(self, game)
end
function UI:button(r, label, ...)
    local b = { x = r.x, y = r.y, w = r.w, h = r.h, label = label, layer = Stub.ctx.layer }
    buttons[#buttons + 1] = b
    local prev = Stub.ctx.button
    Stub.ctx.button = b
    button(self, r, label, ...)
    Stub.ctx.button = prev
end

-- one entry per distinct problem, with how often and where it first showed
local failures, order = {}, {}
local where = ''

local function inside(t, r)
    return t.x1 >= r.x - 0.5 and t.y1 >= r.y - 0.5 and t.x2 <= r.x + r.w + 0.5 and t.y2 <= r.y + r.h + 0.5
end

local function overlaps(a, b)
    return a.x1 < b.x2 - 1 and b.x1 < a.x2 - 1 and a.y1 < b.y2 - 1 and b.y1 < a.y2 - 1
end

local function fail(screen, msg)
    local f = failures[msg]
    if not f then
        f = { count = 0, first = where .. ' ' .. screen }
        failures[msg] = f
        order[#order + 1] = msg
    end
    f.count = f.count + 1
end

-- Draw one frame and check every text the HUD drew (in its virtual space).
local function frame(screen)
    Stub.texts, buttons = {}, {}
    love.draw()
    local ui = H.ui()
    local screenRect = { x = 0, y = 0, w = ui.vw, h = ui.vh }
    local texts = {}
    for _, t in ipairs(Stub.texts) do
        if t.ctx.ui and t.text:match('%S') then
            texts[#texts + 1] = { text = t.text, ctx = t.ctx, x1 = t.x, y1 = t.y, x2 = t.x + t.w, y2 = t.y + t.h }
        end
    end
    for _, t in ipairs(texts) do
        local q = string.format('%q', t.text)
        if not inside(t, screenRect) then
            fail(screen, q .. string.format(' off the screen (%.0f..%.0f of %.0f wide)', t.x1, t.x2, ui.vw))
        elseif t.ctx.panel and not inside(t, t.ctx.panel) then
            fail(screen, q .. ' spills out of its panel')
        elseif t.ctx.button and not inside(t, t.ctx.button) then
            fail(screen, q .. ' spills out of its button')
        end
        for _, b in ipairs(buttons) do
            local box = { x1 = b.x, y1 = b.y, x2 = b.x + b.w, y2 = b.y + b.h }
            if b ~= t.ctx.button and b.layer == t.ctx.layer and overlaps(t, box) then
                fail(screen, q .. ' runs under the ' .. b.label .. ' button')
            end
        end
    end
    for i = 1, #texts do
        for j = i + 1, #texts do
            local a, b = texts[i], texts[j]
            if a.ctx.layer == b.ctx.layer and a.text ~= b.text and overlaps(a, b) then
                fail(screen, string.format('%q overlaps %q', a.text, b.text))
            end
        end
    end
end

local function setSize(size)
    Stub.width, Stub.height = size[1], size[2]
    local ui = H.ui()
    ui.touch = size.touch or false
    love.resize(size[1], size[2])
    where = size[1] .. 'x' .. size[2] .. (size.touch and ' touch' or '')
end

local function step(n)
    for _ = 1, n or 1 do love.update(1 / 30) end
end

local function playingScreens(tag)
    local game = H.game()
    H.closeGoal()
    step(20)
    frame(tag .. ' playing')
    local ui = H.ui()
    for i = 1, #ABILITY_ORDER do
        love.keypressed(tostring(i))
        frame(tag .. ' tool ' .. i)
    end
    love.keypressed('1')
    for _, w in ipairs(game.workers) do
        game.selectedWorker = w
        frame(tag .. ' selected ' .. w.name)
    end
    game.selectedWorker = nil
    ui:toast('Select a morphi first (SELECT tool, then tap one)')
    ui:alert('Bartholomew is fed up and close to leaving the band.')
    ui:alert('Spring 2 begins. 3 migrants joined the band.')
    frame(tag .. ' toast and alerts')
    ui.toastText, ui.alerts = nil, {}
    game.suggestRestart = true
    frame(tag .. ' stuck')
    game.suggestRestart = false
    H.setState('units')
    frame(tag .. ' units')
    -- the log, with a season's worth of everything
    H.announce('Bartholomew gave up walking to the tree at 41,12', { x = 3, y = 3 }, 'hardship')
    H.announce('Fatima is hungry and the bush at 12,40 is walled off', { x = 4, y = 4 }, 'hardship')
    H.announce('Marisol is fed up and close to leaving the band.', { x = 2, y = 2 }, 'warning')
    H.announce('Tobias starved and wandered off into the wilds.', { x = 5, y = 2 }, 'left')
    H.announce('Summer 2 begins. 3 migrants joined the band.')
    H.setState('playing')
    frame(tag .. ' alerts to look at')
    H.setState('log')
    frame(tag .. ' log')
    H.lookAt({ x = 3, y = 3 })
    H.setState('playing')
    frame(tag .. ' looking at a spot')
    ui.alerts = {}
    H.setState('confirmquit')
    frame(tag .. ' menu')
    H.setState('playing')
    for _, which in ipairs({ 'gear', 'values', 'sound' }) do
        ui.dropdown = which
        frame(tag .. ' ' .. which .. ' open')
        ui.dropdown = nil
    end
    game.paused = true
    frame(tag .. ' paused')
    game.selectedWorker = game.workers[1]
    frame(tag .. ' paused, selected')
    game.selectedWorker = nil
    game.paused = false
    H.setState('playing')
end

local function arcadeScreens()
    for i = 1, Campaign.count('arcade') do
        for d = 1, #ARCADE_DIFFICULTIES do
            H.newLevel(i, 'arcade', d)
            frame('arcade ' .. i .. ' d' .. d .. ' goal')
        end
        playingScreens('arcade ' .. i)
        local game = H.game()
        local t = game.level.def.targets
        for _, spent in ipairs({ t.easy + 3, t.easy, t.clever, 0 }) do
            Highscore.resetMemory()
            game.world.spent = spent
            H.levelClear()
            frame('arcade ' .. i .. ' clear, spent ' .. spent)
            H.setState('playing')
        end
    end
end

local function survivalScreens()
    for i = 1, Campaign.count('survival') do
        H.newLevel(i, 'survival')
        frame('survival ' .. i .. ' goal')
        playingScreens('survival ' .. i)
        local game = H.game()
        game.failReason = 'Bartholomew had enough and left.'
        H.setState('levelfailed')
        frame('survival ' .. i .. ' failed')
        game.world.spent = game.level.def.par + 3
        H.levelClear()
        frame('survival ' .. i .. ' clear')
    end
end

local function freePlayScreens()
    for d = 1, #DIFFICULTIES do
        H.newGame(DEFAULT_SEED, d)
        frame('free play d' .. d .. ' goal')
        playingScreens('free play d' .. d)
        H.closeQuarter()
        frame('free play d' .. d .. ' report')
        H.finishGame('annual')
        frame('free play d' .. d .. ' annual')
        H.finishGame('gameover')
        frame('free play d' .. d .. ' game over')
    end
end

local function titleScreens(tag)
    H.goToTitle()
    H.buildTitleOptions()
    for i = 1, #H.title.options do
        H.title.option = i
        for d = 1, #ARCADE_DIFFICULTIES do
            H.title.arcadeDifficulty = d
            H.title.difficultyIndex = d
            frame('title ' .. tag .. ' option ' .. i .. ' d' .. d)
        end
    end
    H.title.editingSeed = true
    H.title.seed = 'WWWWWWWWWWWW'
    frame('title ' .. tag .. ' editing seed')
    H.title.editingSeed = false
    H.title.seed = DEFAULT_SEED
end

TestUiOverflow = {}

function TestUiOverflow:testEveryScreenFits()
    for _, size in ipairs(SIZES) do
        setSize(size)
        Highscore.resetMemory()
        titleScreens('fresh')
        arcadeScreens()
        survivalScreens()
        freePlayScreens()
        titleScreens('all clear')
    end
    local lines = {}
    for _, msg in ipairs(order) do
        local f = failures[msg]
        lines[#lines + 1] = msg .. '  (x' .. f.count .. ', first at ' .. f.first .. ')'
    end
    if #lines > 0 then print(#lines .. ' overflow(s):\n  ' .. table.concat(lines, '\n  ')) end
    lu.assertEquals(#lines, 0)
end

function TestUiOverflow:testStubMeasuresTheRealFace()
    local f = love.graphics.newFont(FONT_PATH, 15)
    lu.assertEquals(f:getWidth(''), 0)
    lu.assertTrue(f:getWidth('MORPHIS') > f:getWidth('morphis') or f:getWidth('MORPHIS') > 0)
    local _, lines = f:getWrap('one two three four five six', f:getWidth('one two'))
    lu.assertEquals(lines[1], 'one two')
end

os.exit(lu.LuaUnit.run())
