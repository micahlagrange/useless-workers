-- Morphis. A small band settling the harsh wilds. You shape the land; they look after themselves.
require('src.constants')
local Util = require('src.util')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Worker = require('src.worker')
local JobSets = require('src.jobsets')
local Scoring = require('src.scoring')
local Abilities = require('src.abilities')
local Highscore = require('src.highscore')
local Campaign = require('src.campaign')
local Camera = require('src.camera')
local Tileset = require('src.tileset')
local UI = require('src.ui')
local Effects = require('src.effects')
local Audio = require('src.audio')
local Stats = require('src.stats')
local Version = require('src.version')

love.graphics.setDefaultFilter('nearest', 'nearest')

local state = 'title'
local ui
local game = {}
local title = { difficultyIndex = DEFAULT_DIFFICULTY, arcadeDifficulty = DEFAULT_ARCADE_DIFFICULTY, seed = DEFAULT_SEED, editingSeed = false, muted = false, options = {}, option = 1 }

-- The title offers the arcade levels first, then the retired survival
-- levels, then free play. A level is locked until the one before it is
-- clear. Progress lives in the high score store under string keys.
local function levelsUnlocked(set)
    return math.max(1, Highscore.load(Campaign.unlockKey[set]))
end

local function buildTitleOptions()
    title.options = {}
    for _, set in ipairs({ 'arcade', 'survival' }) do
        local unlocked = levelsUnlocked(set)
        local key = Campaign.saveKey[set]
        for i = 1, Campaign.count(set) do
            local cleared = Highscore.load(key .. i .. '_cleared') == 1
            title.options[#title.options + 1] = {
                kind = 'level', set = set, index = i, def = Campaign.list(set)[i], locked = i > unlocked,
                best = cleared and Highscore.load(key .. i .. '_best') or nil,
            }
        end
    end
    title.options[#title.options + 1] = { kind = 'free' }
    if title.option > #title.options then title.option = 1 end
end

-- 'level' (survival) and 'arcade' are both hand built levels.
local function isLevelMode()
    return game.mode == 'level' or game.mode == 'arcade'
end

-- Each mode has its own tool bar; the HUD lays itself out around it.
local function setTools(order)
    ABILITY_ORDER = order
    ui:layout(love.graphics.getDimensions())
end
-- touch: every finger on the screen, by id. Two fingers pinch to zoom and pan.
local touches = {}
local touchCount = 0
local pinch = nil
-- On a touch screen the first finger is the pointer: taps and drags come
-- from the touch events themselves. The mouse events SDL makes up from a
-- finger are ignored, because on iOS they can stop coming after a touch is
-- cancelled, and every tap then went nowhere.
local primary = nil          -- the finger acting as the pointer, if any
local pointerX, pointerY = 0, 0
local lastTouchAt = -10      -- a real mouse is listened to again a moment after the last touch
local function pointerPosition()
    if ui.touch then return pointerX, pointerY end
    return love.mouse.getPosition()
end
-- FINGERS (gear menu, or F3): draws every finger the game is tracking and
-- every one LOVE says is down, to catch fingers that get stuck.
local fingerDebug = false
-- the tester's corner, EXPORT and HISTORY: where to go back to, the note
-- being typed, what the save said and how far HISTORY is scrolled
-- back: the screen EXPORT or HISTORY returns to; toolsBack: the one the
-- tester tools (DEV) return to
local sub = { back = 'playing', toolsBack = 'playing', text = '', saved = nil, scroll = 0, fit = 1 }
local exportBoxClosed -- defined with the EXPORT screen, called from love.update
local debugClock = 0
local reportTimer = 0
local musicStarted = false
local PAN_SPEED = 700
-- Fast forward: the simulation runs this many steps a frame. Every arcade
-- level starts at 1x, so the opening is never a blur.
local SIM_SPEEDS = { 1, 2, 4 }
local simSpeed = 1

local function isWeb()
    return love.system.getOS() == 'Web'
end

-- No pointer to hide on a touch screen, and hiding it on a laptop with a
-- touch screen would be rude.
local function hideCursor()
    if not (ui and ui.touch) then love.mouse.setVisible(false) end
end

local function startMusic()
    if not musicStarted then
        Audio.playBGM('theme')
        musicStarted = true
    end
end

-- Game setup ---------------------------------------------------------------

local NODE_WORDS = { bush = 'berry bush', tree = 'tree', ore = 'shiny', grass = 'grass tuft', leaves = 'leaf pile', critter = 'critter' }

-- Everything announced goes into the log (LOG up top), with when, what
-- kind and where, so it can be read later and looked at on the map. Only
-- bad news pops up over the map (Micah, 2026-10-21: alerts got in the way):
-- a morphi fed up and close to leaving, or one that left or starved.
local ALERT_KINDS = { warning = true, left = true }
local function announce(text, tile, kind)
    if ALERT_KINDS[kind] then ui:alert(text, tile) end
    if not game.log then return end
    game.log[#game.log + 1] = {
        text = text, tile = tile, kind = kind or 'news',
        season = game.scoring and game.scoring:seasonLabel() or '', clock = game.clock or 0,
    }
    if #game.log > 300 then table.remove(game.log, 1) end
end

local function onComplain(worker, reason, node)
    local where = node and ((NODE_WORDS[node.kind] or node.kind or 'work') .. ' at ' .. node.x .. ',' .. node.y) or 'somewhere'
    local text
    if reason == 'hungry' then
        text = worker.name .. ' is hungry and the ' .. where .. ' is out of reach'
    elseif reason == 'slow' then
        text = worker.name .. ' gave up walking to the ' .. where
    elseif reason == 'bored' then
        -- why, naming the jobs: the main one and the neutral one (the
        -- disliked job is the last resort, not worth an alert)
        local shown = {}
        for _, r in ipairs(worker.idleWhy or {}) do
            if r.slot ~= 'disliked' then shown[#shown + 1] = r end
        end
        if #shown > 0 then
            text = worker.name .. ' has nothing to do. ' .. Worker.idleText(shown, worker.jobSet and not worker.jobSet.neutral, worker.unstaffed)
        else
            text = worker.name .. ' has nothing to do'
        end
    else
        text = worker.name .. " can't reach the " .. where
    end
    -- a hardship pointing at a site (out of reach work to build or dig) has no node kind
    announce(text, node and { x = node.x, y = node.y } or nil, 'hardship')
    if game.stats then game.stats:event('hardship', game, worker.name, reason) end
    Audio.playSFX('complain')
end

local function onWorkerEvent(worker, name, data)
    if name == 'eat' then Audio.playSFX('eat')
    elseif name == 'deliver' then Audio.playSFX('deliver')
    elseif name == 'pickup' then Audio.playSFX('click')
    elseif name == 'mined' then Audio.playSFX('dig')
    elseif name == 'shiny' and game.mode == 'free' then
        Audio.playSFX('deliver')
        announce(worker.name .. ' dug up a shiny!', data, 'news')
    elseif name == 'built' then Audio.playSFX('hire')
    elseif name == 'break' then Audio.playSFX('settled')
    elseif name == 'work' then Audio.playSFX(data == 'ore' and 'dig' or (data == 'tree' and 'line' or 'click'))
    elseif name == 'trade' and game.mode == 'free' then
        local t = worker:tile()
        Audio.playSFX('hire')
        if game.stats then game.stats:event('trade', game, worker.name .. ' and ' .. data.partner.name, nil, t) end
        announce(worker.name .. ' and ' .. data.partner.name .. ' swapped snacks at the home nest'
            .. (data.gifts > 0 and (', ' .. data.gifts .. ' favourite treat' .. (data.gifts == 1 and '' or 's') .. ' sweetening it') or '') .. '.', { x = t.x, y = t.y }, 'news')
    elseif name == 'lowmorale' then
        local t = worker:tile()
        announce(worker.name .. ' is very grumpy and thinking about leaving.', { x = t.x, y = t.y }, 'warning')
    elseif name == 'quit' then
        Audio.playSFX('quit')
        local t = worker:tile()
        if game.stats then game.stats:event(data == 'morale' and 'left' or 'starved', game, worker.name, nil, t) end
        if data == 'morale' then
            announce(worker.name .. ' packed a tiny bag and left. Too many grumbles, not enough cuddles.', { x = t.x, y = t.y }, 'left')
        else
            announce(worker.name .. ' got far too hungry and toddled off to find snacks elsewhere.', { x = t.x, y = t.y }, 'left')
        end
        if game.mode == 'level' and (state == 'playing' or state == 'units' or state == 'jobs') then
            game.failReason = worker.name .. (data == 'morale' and ' had enough and left.' or ' starved.')
            state = 'levelfailed'
            love.mouse.setVisible(true)
        end
    end
end

-- The job sets of the band as it stands, for dealing an immigrant's.
local function bandJobSets()
    local out = {}
    for _, w in ipairs(game.workers) do
        if w.jobSet and w:isWorking() then out[#out + 1] = w.jobSet end
    end
    return out
end

-- migrants: true for arrivals after the start, which the stats count. Free
-- play deals each arrival's jobs (src/jobsets.lua) from a random stream of
-- its own, so nothing else about the seed changes; the species comes round
-- in HIRE_SHEETS order and decides only looks and tastes.
local function hire(n, migrants)
    local spots = game.world:spawnTiles(3)
    if #spots == 0 then spots = { { x = game.world.breakroom.x, y = game.world.breakroom.y } } end
    local free = game.mode == 'free'
    local dealt = (free and not migrants) and JobSets.dealStart(game.jobRng, n) or nil
    for i = 1, n do
        game.hired = game.hired + 1
        local spot = spots[(game.hired - 1) % #spots + 1]
        local jobs = free and (dealt and dealt[i] or JobSets.dealOne(game.jobRng, bandJobSets())) or nil
        local role = jobs and jobs.main or HIRE_ORDER[(game.hired - 1) % #HIRE_ORDER + 1]
        local sheet = HIRE_SHEETS[(game.hired - 1) % #HIRE_SHEETS + 1]
        -- arrivals come in a little less fed one after another, so the band
        -- does not all get hungry at once
        local start = (game.scoring.difficulty.startHunger or STARTING_HUNGER) - ((game.hired - 1) % 5) * 6
        local worker = Worker.new(game.world, game.jobs, game.scoring, game.rng, {
            x = spot.x, y = spot.y,
            role = role,
            jobs = jobs,
            band = game.workers,
            sheet = sheet,
            name = MORPHI_NAMES[(game.hired - 1) % #MORPHI_NAMES + 1],
            drain = game.scoring.drain,
            hunger = start,
            wilds = game.mode == 'free',
            onComplain = onComplain,
            onEvent = onWorkerEvent,
        })
        table.insert(game.workers, worker)
        if migrants and game.stats then
            game.stats:event('arrived', game, worker.name, jobs and (jobs.main .. '/' .. (jobs.neutral or 'none') .. '/' .. jobs.disliked) or role)
        end
    end
end

local function onReady(node)
    game.jobs:postNode(node)
end

local function onEffect(name, data)
    if name == 'mine' then
        Audio.playSFX('click')
        ui:toast(data.count .. ' tile' .. (data.count == 1 and '' or 's') .. ' marked for digging')
    elseif name == 'unmark' then
        Audio.playSFX('click')
        if data.kind then
            ui:toast((ABILITY_LABEL[data.kind] or data.kind:upper()) .. ' designation cancelled')
        else
            ui:toast(data.count .. ' mark' .. (data.count == 1 and '' or 's') .. ' cleared')
        end
    elseif name == 'site' then
        Audio.playSFX('line')
    end
end

local function newGame(seedString, difficultyIndex)
    game = {}
    setTools(TOOLS_SURVIVAL)
    game.seedString = seedString
    game.seedNumber = Rng.seedToNumber(seedString)
    game.rng = Rng.new(game.seedNumber)
    game.scoring = Scoring.new(difficultyIndex)
    game.world = World.generate(game.seedNumber, game.rng)
    game.jobs = Jobs.new()
    game.world.stock = { logs = STARTING_STOCK.logs, gold = STARTING_STOCK.gold, grass = STARTING_STOCK.grass, leaves = STARTING_STOCK.leaves }
    game.world:spawnAllNodes(NODES_INITIAL)
    -- everything standing at the start is already workable
    for _, node in ipairs(game.world.nodes) do
        if node.ready then game.jobs:postNode(node) end
    end
    game.workers = {}
    game.hired = 0
    game.jobRng = JobSets.rngFor(game.seedNumber)
    game.clock = 0
    game.staffCount = 0
    game.averageHunger = 100
    game.abilities = Abilities.new(game.world, game.jobs, onEffect)
    game.view = Tileset.newView(game.world)
    game.tileset = Tileset.current()
    game.camera = Camera.new(game.world.w, game.world.h, love.graphics.getDimensions())
    game.camera:setInsets(TOP_BAR_H * ui.scale, BOTTOM_BAR_H * ui.scale)
    game.camera.scale = 2
    game.camera:centerOn(game.world.breakroom.cx, game.world.breakroom.cy)
    game.selectedWorker = nil
    game.follow = false
    game.lineStart = nil
    game.dragging = false
    game.report = nil
    game.highScore = Highscore.load(difficultyIndex)
    game.isNewHigh = false
    game.mode = 'free'
    game.levels = Campaign.levels
    Effects.clear()
    ui:clear()
    game.stats = Stats.new({ mode = 'free', seed = seedString, difficulty = DIFFICULTIES[difficultyIndex].name, build = Version.build })
    hire(DIFFICULTIES[difficultyIndex].workers)
    game.log = {}
    announce('Mark a STASH (or a BASKET, 1 grass, holds 4) so foragers have somewhere to put berries. BRIDGE the streams to reach the far banks.')
    game.started = false
    state = 'goal'
    love.mouse.setVisible(true)
end

-- A hand built level: its own map, morphis and points. Survival has a
-- clock, and the clock ending means a clear. Arcade has no clock: the
-- level is clear when every morphi has eaten.
local function newLevel(index, set, difficulty)
    set = set or 'arcade'
    local run = Campaign.load(index, Rng.new(index), set, difficulty or title.arcadeDifficulty)
    game = {}
    game.log = {}
    game.mode = set == 'arcade' and 'arcade' or 'level'
    if set == 'arcade' then simSpeed = 1 end
    setTools(set == 'arcade' and TOOLS_ARCADE or TOOLS_SURVIVAL)
    game.level = run
    game.levels = Campaign.list(set)
    game.seedString = set .. ' ' .. index
    game.rng = Rng.new(index)
    game.scoring = Scoring.new(DEFAULT_DIFFICULTY)
    game.scoring.drain = run.def.drain or 0
    game.scoring.quarterTimer = run.def.seconds or 1e9
    game.world = run.world
    game.jobs = Jobs.new()
    for _, node in ipairs(game.world.nodes) do
        if node.ready then game.jobs:postNode(node) end
    end
    game.workers = {}
    game.hired = #run.specs
    game.clock = 0
    game.staffCount = #run.specs
    game.averageHunger = run.def.hunger or HUNGER_MAX
    game.abilities = Abilities.new(game.world, game.jobs, onEffect)
    game.view = Tileset.newView(game.world)
    game.tileset = Tileset.current()
    game.camera = Camera.new(game.world.w, game.world.h, love.graphics.getDimensions())
    game.camera:setInsets(TOP_BAR_H * ui.scale, BOTTOM_BAR_H * ui.scale)
    game.camera:fitWorld()
    game.selectedWorker = nil
    game.follow = false
    game.lineStart = nil
    game.dragging = false
    game.report = nil
    game.highScore = 0
    game.isNewHigh = false
    game.stats = Stats.new({ mode = game.mode, seed = game.seedString, level = run.def.name, build = Version.build })
    for _, spec in ipairs(run.specs) do
        table.insert(game.workers, Worker.new(game.world, game.jobs, game.scoring, game.rng, {
            x = spec.x, y = spec.y, role = spec.role, sheet = spec.sheet, name = spec.name,
            diet = spec.diet, hunger = spec.hunger, drain = run.def.drain,
            onComplain = onComplain, onEvent = onWorkerEvent,
        }))
    end
    Effects.clear()
    ui:clear()
    game.started = false
    state = 'goal'
    love.mouse.setVisible(true)
end

local function closeGoal()
    game.started = true
    state = 'playing'
    hideCursor()
end

local function openGoal()
    state = 'goal'
    love.mouse.setVisible(true)
end

local function levelClear()
    local lv = game.level
    local spent = game.world.spent
    lv.stars = Campaign.stars(spent, lv.def)
    lv.perfect = lv.set == 'arcade' and spent == 0
    local key = Campaign.saveKey[lv.set] .. lv.index
    local cleared = Highscore.load(key .. '_cleared') == 1
    lv.isNewBest = not cleared or spent < Highscore.load(key .. '_best')
    if lv.isNewBest then Highscore.set(key .. '_best', spent) end
    Highscore.set(key .. '_cleared', 1)
    Highscore.set(Campaign.unlockKey[lv.set], math.max(levelsUnlocked(lv.set), lv.index + 1))
    state = 'levelclear'
    love.mouse.setVisible(true)
    Audio.playSFX('win')
end

local function staffStats()
    local count, hungerSum = 0, 0
    for _, w in ipairs(game.workers) do
        if w:isWorking() then
            count = count + 1
            hungerSum = hungerSum + w.hunger
        end
    end
    return count, (count > 0 and hungerSum / count or nil)
end

local function finishGame(nextState)
    local final = game.scoring:finalScore()
    game.isNewHigh = Highscore.save(game.scoring.difficultyIndex, final)
    game.highScore = Highscore.load(game.scoring.difficultyIndex)
    state = nextState
    love.mouse.setVisible(true)
    Audio.playSFX(nextState == 'annual' and 'win' or 'quit')
end

local function closeQuarter()
    local count = staffStats()
    game.report = game.scoring:closeQuarter(count)
    -- new growth comes up mostly where nobody can get at it yet
    -- leaves blow in most at the start of Autumn (the third season)
    local counts = {}
    for k, v in pairs(NODES_PER_QUARTER) do counts[k] = v end
    if (game.scoring.quarter - 1) % 4 + 1 == 3 then counts.leaves = counts.leaves * LEAVES_AUTUMN end
    for _, node in ipairs(game.world:spawnAllNodes(counts, game.mode == 'free' and NODE_ENCLOSED_LATER or nil)) do
        if node.ready then game.jobs:postNode(node) end
    end
    for _, w in ipairs(game.workers) do w.drain = game.scoring.drain end
    if game.report.hires > 0 then
        hire(game.report.hires, true)
        Audio.playSFX('hire')
    end
    Audio.playSFX('report')
    reportTimer = 0
    state = 'report'
    love.mouse.setVisible(true)
end

local function continueFromReport()
    if game.scoring:yearComplete() then
        finishGame('annual')
    else
        state = 'playing'
        hideCursor()
        announce(game.scoring:seasonLabel() .. ' begins. ' .. game.report.hires .. ' little blob' .. (game.report.hires == 1 and '' or 's') .. ' wandered in to join the bunch.')
    end
end

local function workerAt(tile)
    local best, bestD = nil, 1.5
    for _, w in ipairs(game.workers) do
        if w:isWorking() then
            local t = w:tile()
            local d = Util.dist(t.x, t.y, tile.x, tile.y)
            if d < bestD then best, bestD = w, d end
        end
    end
    return best
end

local function goToTitle()
    state = 'title'
    love.mouse.setVisible(true)
    title.editingSeed = false
    buildTitleOptions()
end

local function titleMove(step)
    title.option = (title.option - 1 + step) % #title.options + 1
    title.editingSeed = false
end

-- UP / DOWN and the < > under the name: free play's wilds, or the arcade budget.
local function difficultyMove(step)
    local opt0 = title.options[title.option]
    if opt0 and opt0.kind == 'free' and FREE_PLAY_DIFFICULTIES <= 1 then return end
    local opt = title.options[title.option]
    if opt.kind == 'free' then
        title.difficultyIndex = (title.difficultyIndex - 1 + step) % #DIFFICULTIES + 1
    elseif opt.set == 'arcade' then
        title.arcadeDifficulty = (title.arcadeDifficulty - 1 + step) % #ARCADE_DIFFICULTIES + 1
    end
end

local function nextLevelOrTitle()
    if game.level.index < Campaign.count(game.level.set) then
        newLevel(game.level.index + 1, game.level.set, game.level.difficulty)
    else
        goToTitle()
    end
end

-- LOVE callbacks -----------------------------------------------------------

function love.load()
    ui = UI.new()
    Audio.loadVolumes()
    Tileset.load()
    love.keyboard.setKeyRepeat(true)
    buildTitleOptions()
    -- start on the furthest unlocked arcade level
    title.option = math.min(levelsUnlocked('arcade'), Campaign.count('arcade'))
end

function love.resize(w, h)
    ui:layout(w, h)
    if game and game.camera then
        game.camera:setView(w, h)
        game.camera:setInsets(TOP_BAR_H * ui.scale, BOTTOM_BAR_H * ui.scale)
        if isLevelMode() and not game.started then game.camera:fitWorld() end
    end
end


-- Panning, following and effects: once a frame, paused or not.
local function updateCamera(dt)
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') or love.keyboard.isDown('up') then dy = dy - 1 end
    if love.keyboard.isDown('s') or love.keyboard.isDown('down') then dy = dy + 1 end
    if love.keyboard.isDown('a') or love.keyboard.isDown('left') then dx = dx - 1 end
    if love.keyboard.isDown('d') or love.keyboard.isDown('right') then dx = dx + 1 end
    if dx ~= 0 or dy ~= 0 then
        game.follow = false
        game.camera:pan(dx * PAN_SPEED * dt, dy * PAN_SPEED * dt)
    end
    if game.follow then
        local w = game.selectedWorker
        if w and w.alive then
            game.camera:centerOn(w.x, w.y)
        else
            game.follow = false
        end
    end
    Effects.update(dt)
end

-- substep: an extra fast forward step this frame; the camera and effects
-- only move once a frame.
local function updatePlaying(dt, substep)
    game.clock = game.clock + dt
    game.jobs:update(dt)
    game.world:update(dt, onReady)
    for _, w in ipairs(game.workers) do
        w:update(dt, game.clock)
    end
    for i = #game.workers, 1, -1 do
        if not game.workers[i].alive then
            if game.selectedWorker == game.workers[i] then game.selectedWorker = nil end
            table.remove(game.workers, i)
        end
    end
    local count, avg = staffStats()
    game.staffCount = count
    game.averageHunger = avg or game.averageHunger
    if game.stats then game.stats:update(game) end
    if count == 0 and not isLevelMode() then
        finishGame('gameover')
        return
    end
    if game.mode == 'arcade' and Campaign.allAte(game.workers) then
        levelClear()
        return
    end
    -- Stuck: the logs are gone, nothing is being built, and nobody who still
    -- wants a meal can walk to one. After five seconds of that, suggest a restart.
    if game.mode == 'arcade' then
        local stuck = game.world.stock.logs == 0
        if stuck then
            for _, site in ipairs(game.world.sites) do
                if site.claimedBy ~= nil then stuck = false break end
            end
        end
        if stuck then
            for _, w in ipairs(game.workers) do
                if w.alive and not w.ate and w:canReachFood() then stuck = false break end
            end
        end
        game.stuckTimer = stuck and (game.stuckTimer or 0) + dt or 0
        game.suggestRestart = game.stuckTimer >= 5
    end
    if game.scoring:update(dt, avg) then
        if game.mode == 'level' then levelClear() else closeQuarter() end
        return
    end
    if not substep then updateCamera(dt) end
end

-- Fingers are counted from what LOVE says is on the screen right now, not by
-- adding presses and subtracting releases: a release that never arrives (iOS
-- cancels touches mid gesture) would otherwise leave a phantom finger down,
-- every later tap read as a pinch and ignored.
local function syncTouches()
    if not love.touch then return end
    local live = {}
    for _, id in ipairs(love.touch.getTouches()) do live[id] = true end
    local n = 0
    for id in pairs(touches) do
        if live[id] then n = n + 1 else touches[id] = nil end
    end
    -- the pointer finger vanished without a release: call off what it began
    if primary and not live[primary] then
        primary = nil
        if game then game.panStart, game.lineStart, game.lineCost = nil, nil, nil end
    end
    touchCount = n
    if touchCount < 2 then pinch = nil end
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    debugClock = debugClock + dt
    Audio.update(dt)
    syncTouches()
    if state == 'playing' or state == 'units' or state == 'log' or state == 'jobs' then
        game.speed = simSpeed
        if game.paused then
            -- paused: nothing in the world moves, but the camera and the
            -- tools still work
            updateCamera(dt)
        else
            for step = 1, simSpeed do
                updatePlaying(dt, step > 1)
                if state ~= 'playing' and state ~= 'units' and state ~= 'log' and state ~= 'jobs' then break end
            end
        end
        ui:update(dt)
    elseif state == 'report' then
        reportTimer = reportTimer + dt
        if reportTimer > 15 then continueFromReport() end
    end
    if state == 'export' then exportBoxClosed() end
    -- 'confirmquit' and 'goal' are pauses: nothing updates
end

local function drawWorld()
    local cam = game.camera
    game.view:rebuildCanvas() -- before the camera transform, see View:rebuildCanvas
    -- beyond the map: dark ground, not a black hole
    local out = game.view.outside
    love.graphics.setColor(out[1], out[2], out[3], 1)
    love.graphics.rectangle('fill', 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    cam:apply()
    Effects.applyShake()
    game.view:drawWorld()
    game.view:drawBreakroom()
    game.view:drawStorage()
    game.view:drawFloors()
    game.view:drawBeds()
    game.view:drawNodes(game.clock)
    game.view:drawItems(game.clock)
    game.view:drawSites(game.clock)
    -- tiles the alerts are pointing at
    local pulse = 0.4 + 0.4 * math.abs(math.sin(game.clock * 6))
    for _, t in ipairs(ui:alertTiles()) do
        game.view:drawTileOutline(t.x, t.y, { 1, 0.3, 0.2, pulse })
    end
    if game.focus then game.view:drawFocus(game.focus.x, game.focus.y, game.clock) end
    -- cursor preview
    if state == 'playing' then
        local mx, my = pointerPosition()
        if not ui:isOverBars(mx, my) then
            local tile = cam:toTile(mx, my)
            local tool = game.abilities.selected
            -- furniture shows a ghost where it will go: under the mouse, or
            -- under the finger while it is down (a lifted finger has no hover)
            local ghost = game.abilities:ghostKind()
            if ghost and (game.lineStart or not ui.touch) then
                local t = game.world:get(tile.x, tile.y)
                if t and t.site and t.site.kind == ghost then
                    -- lifting here takes it back
                    for _, p in ipairs(game.world:siteTiles(ghost, t.site.x, t.site.y)) do
                        game.view:drawTileFill(p.x, p.y, { 1, 0.3, 0.25, 0.5 })
                    end
                else
                    local ok = game.world:canSite(ghost, tile.x, tile.y) and game.abilities:canAfford(tool)
                    game.view:drawGhost(ghost, tile.x, tile.y, ok)
                end
            elseif game.lineStart then
                -- what the drag will do on release: red where it clears marks
                local tiles, clearing = game.abilities:dragPlan(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
                for _, p in ipairs(tiles) do
                    local t = game.world:get(p.x, p.y)
                    local color = { 1, 1, 1, 0.15 }
                    if clearing then
                        if t and t.site then color = { 1, 0.3, 0.25, 0.5 } end
                    elseif tool == ABILITY_MINE then
                        if t and (t.type == TILE_STONE or t.type == TILE_SNOW) then color = { 1, 0.6, 0.2, 0.45 } end
                    elseif tool == ABILITY_BRIDGE then
                        if t and t.type == TILE_WATER then color = { 0.9, 0.7, 0.3, 0.55 } end
                    else
                        color = { 0.85, 0.9, 0.5, 0.4 }
                    end
                    game.view:drawTileFill(p.x, p.y, color)
                end
                game.lineCost = nil
                if tool == ABILITY_BRIDGE and not clearing then
                    local _, cost = game.abilities:lineQuote(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
                    game.lineCost = cost
                end
            else
                game.view:drawTileOutline(tile.x, tile.y, { 1, 1, 1, 0.8 })
            end
        end
    end
    game.view:drawWorkers(game.workers, game.clock, game.selectedWorker)
    Effects.draw()
    cam:reset()
end

local function drawScene()
    if state == 'title' then
        title.muted = Audio.isMuted()
        ui:beginScaled()
        ui:drawTitle(title, Highscore.load(title.difficultyIndex))
        ui:endScaled()
        return
    end
    drawWorld()
    game.muted = Audio.isMuted()
    ui:beginScaled()
    ui:drawHUD(game)
    if state == 'report' then
        ui:drawReport(game.report, game.scoring)
    elseif state == 'gameover' then
        ui:drawGameOver(game.scoring, game.highScore, game.isNewHigh, game.stats)
    elseif state == 'annual' then
        ui:drawAnnual(game.scoring, game.highScore, game.isNewHigh, game.stats)
    elseif state == 'tools' then
        ui:drawTools(fingerDebug)
    elseif state == 'export' then
        ui:drawExport(sub.text, sub.saved)
    elseif state == 'history' then
        sub.fit = ui:drawHistory(game.stats and game.stats:history() or {}, sub.scroll)
    elseif state == 'confirmquit' then
        ui:drawConfirmQuit()
    elseif state == 'goal' then
        ui:drawGoal(game)
    elseif state == 'levelclear' then
        ui:drawLevelClear(game)
    elseif state == 'levelfailed' then
        ui:drawLevelFailed(game)
    elseif state == 'units' then
        ui:drawUnits(game, game.view)
    elseif state == 'jobs' then
        ui:drawJobs(game)
    elseif state == 'log' then
        ui:drawLog(game)
    end
    ui:endScaled()
    if state == 'playing' then
        local mx, my = pointerPosition()
        if game.lineStart and game.lineCost and game.abilities.selected == ABILITY_BRIDGE then
            love.graphics.setFont(ui.fonts.small)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print('bridge: ' .. game.lineCost .. ' logs', mx + 18, my + 18)
        end
        ui:drawCursor(game.abilities.selected, mx, my)
    end
end

-- The FINGERS view, in window pixels over everything: filled, numbered
-- circles for the fingers the game is tracking (where each was last seen),
-- hollow rings for the ones LOVE lists as down ('?' if the game is not
-- tracking that one), and a readout of both counts and the pinch.
local function drawFingerDebug()
    local font = ui.fonts.hud
    love.graphics.setFont(font)
    local r = 28 * math.max(1, ui.scale)
    local lines = {}
    local tracked = {}
    for id, t in pairs(touches) do
        tracked[id] = t
        love.graphics.setColor(1, 0.85, 0.2, 0.35)
        love.graphics.circle('fill', t.x, t.y, r)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.setLineWidth(3)
        love.graphics.circle('line', t.x, t.y, r)
        local label = tostring(t.n or '?')
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.print(label, t.x - font:getWidth(label) / 2, t.y - font:getHeight() / 2)
        lines[#lines + 1] = { n = t.n or 99, text = string.format('finger %s  at %d,%d  still for %.1fs', label, t.x, t.y, debugClock - (t.seen or debugClock)) }
    end
    local loveCount = 0
    if love.touch then
        for _, id in ipairs(love.touch.getTouches()) do
            loveCount = loveCount + 1
            local x, y = love.touch.getPosition(id)
            love.graphics.setColor(0.3, 0.8, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.circle('line', x, y, r + 8)
            if not tracked[id] then
                love.graphics.print('?', x - font:getWidth('?') / 2, y - r - 8 - font:getHeight())
                lines[#lines + 1] = { n = 100, text = string.format('LOVE lists a finger at %d,%d the game is not tracking', x, y) }
            end
        end
    end
    table.sort(lines, function(a, b) return a.n < b.n end)
    local count = 0
    for _ in pairs(touches) do count = count + 1 end
    local head = string.format('FINGERS  game: %d   LOVE: %d   pinch: %s', count, loveCount, pinch and 'ON (taps ignored)' or 'off')
    local small = ui.fonts.small
    love.graphics.setFont(small)
    local lh = small:getHeight() + 4
    local w = small:getWidth(head) + 20
    for _, l in ipairs(lines) do w = math.max(w, small:getWidth(l.text) + 20) end
    local y0 = love.graphics.getHeight() * 0.25
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle('fill', 8, y0, w, (#lines + 1) * lh + 10)
    love.graphics.setColor(pinch and 1 or 0.6, pinch and 0.4 or 0.9, pinch and 0.3 or 0.6, 1)
    love.graphics.print(head, 18, y0 + 5)
    love.graphics.setColor(1, 1, 1, 1)
    for i, l in ipairs(lines) do love.graphics.print(l.text, 18, y0 + 5 + i * lh) end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
    drawScene()
    if fingerDebug then drawFingerDebug() end
end

-- Input --------------------------------------------------------------------

local function startFromTitle()
    local opt = title.options[title.option]
    if opt.kind == 'level' then
        if opt.locked then ui:toast('Clear ' .. Campaign.title[opt.set]:lower() .. ' level ' .. (opt.index - 1) .. ' first') return end
        startMusic()
        newLevel(opt.index, opt.set, title.arcadeDifficulty)
        return
    end
    startMusic()
    title.editingSeed = false
    if title.seed == '' then title.seed = DEFAULT_SEED end
    newGame(title.seed, title.difficultyIndex)
end

function closeUnits()
    state = 'playing'
    hideCursor()
end

-- Follow the previous (-1) or next (1) morphi still in the band.
local function followNext(step)
    local band = {}
    for _, w in ipairs(game.workers) do
        if w.alive and w.state ~= 'quitting' then band[#band + 1] = w end
    end
    if #band == 0 then return end
    local at = 0
    for i, w in ipairs(band) do if w == game.selectedWorker then at = i end end
    if at == 0 then at = step > 0 and 0 or 1 end
    local w = band[(at - 1 + step) % #band + 1]
    game.selectedWorker = w
    game.abilities:select(ABILITY_SELECT)
    if game.follow then
        ui:toast('Following ' .. w.name)
    else
        -- not following: pick it and look at it, the camera stays free
        game.focus = nil
        local t = w:tile()
        game.camera:centerOn((t.x - 0.5) * TILE_SIZE, (t.y - 0.5) * TILE_SIZE)
        ui:toast(w.name)
    end
end

local function toggleFollow()
    if game.selectedWorker and game.selectedWorker.alive then
        game.follow = not game.follow
        ui:toast(game.follow and ('Following ' .. game.selectedWorker.name) or 'Camera free')
    else
        ui:toast('Select a morphi first (SELECT tool, then tap one)')
    end
end

local function openUnits()
    state = 'units'
    love.mouse.setVisible(true)
end

-- The job screen for the picked morphi (free play: main, neutral, disliked).
local function openJobs()
    local w = game.selectedWorker
    if not (w and w.alive and w.jobSet) then
        ui:toast(game.mode == 'free' and 'Select a morphi first (SELECT tool, then tap one)' or 'Each morphi here has one fixed job')
        return
    end
    state = 'jobs'
    love.mouse.setVisible(true)
    Audio.playSFX('click')
end

local function closeJobs()
    state = 'playing'
    hideCursor()
end

-- A tap on the job screen: 'job:<slot>:<job or none>'.
local function pressJob(id)
    local w = game.selectedWorker
    if not (w and w.jobSet) then closeJobs() return end
    local slot, job = id:match('^job:(%a+):(%a+)$')
    if job == 'none' then job = nil end
    local before = w.jobSet[slot]
    local ok, why = w:setJob(slot, job)
    if not ok then
        ui:toast(w.name .. ': ' .. why)
    elseif before ~= w.jobSet[slot] then
        ui:toast(w.name .. "'s " .. slot .. ' job: ' .. (job and ROLES[job].label:lower() or 'none'))
        if game.stats then game.stats:event('jobs', game, w.name, w.jobSet.main .. '/' .. (w.jobSet.neutral or 'none') .. '/' .. w.jobSet.disliked) end
    end
end

local function openMenu()
    state = 'confirmquit'
    love.mouse.setVisible(true)
end

-- EXPORT, HISTORY and the tester's corner open over another screen and go
-- back to it.
local function openSub(which)
    if which == 'tools' then sub.toolsBack = state
    elseif state ~= 'export' and state ~= 'history' then sub.back = state end
    state = which
    sub.saved, sub.scroll = nil, 0
    love.keyboard.setTextInput(which == 'export')
    love.mouse.setVisible(true)
end

-- Back to the screen underneath, and to play with the pointer hidden.
local function backTo(s)
    love.keyboard.setTextInput(false)
    state = s
    if s == 'playing' then hideCursor() end
end

local function closeSub()
    backTo(sub.back)
end

-- The screen the run was exported from, under any tester screens.
local function underneath()
    return sub.back == 'tools' and sub.toolsBack or sub.back
end

-- The run's audit log, with the player's note, as JSON text to paste into
-- the run viewer (tools/stats_viewer.html). On the web the page shows it in
-- a text box over the game, with COPY and DOWNLOAD (tools/patch_lovejs.py
-- watches exports/ in the save folder); on the desktop the game shows it
-- with its own COPY and DOWNLOAD.
local function exportRun()
    if not game.stats then return end
    game.stats:update(game)
    local name = Stats.runName(sub.text, os.date('%Y%m%d-%H%M%S'), Version.build)
    local data = game.stats:export(sub.text, {
        exportedAt = os.date('%Y-%m-%d %H:%M:%S'), endedAs = underneath(), clock = math.floor(game.clock or 0), runName = name,
    })
    love.keyboard.setTextInput(false)
    sub.saved = { json = data, name = name, days = #game.stats.days, web = isWeb() }
    sub.text = ''
    if isWeb() then
        love.filesystem.createDirectory('exports')
        local ok, err = love.filesystem.write('exports/' .. name, data)
        if not ok then sub.saved.message = 'Could not show the text box: ' .. tostring(err) end
    end
    Audio.playSFX('report')
end

-- DOWNLOAD on the desktop: the run into the save folder's stats/.
local function downloadRun()
    love.filesystem.createDirectory('stats')
    local ok, err = love.filesystem.write('stats/' .. sub.saved.name, sub.saved.json)
    sub.saved.message = ok and ('Saved to ' .. love.filesystem.getSaveDirectory() .. '/stats/' .. sub.saved.name)
        or ('Could not save: ' .. tostring(err))
end

-- Leaving the export screen also takes down the web page's text box.
local function closeExport()
    if sub.saved and sub.saved.web then love.filesystem.remove('exports/' .. sub.saved.name) end
    sub.saved = nil
    closeSub()
end

-- On the web, closing the page's text box deletes the file: leave the
-- export screen with it.
function exportBoxClosed()
    if sub.saved and sub.saved.web and not sub.saved.message
        and not love.filesystem.getInfo('exports/' .. sub.saved.name) then
        sub.saved = nil
        closeSub()
    end
end

-- The same level, or the same free play seed, from the top.
local function restartGame()
    Audio.playSFX('click')
    if isLevelMode() then
        newLevel(game.level.index, game.level.set, game.level.difficulty)
    else
        newGame(game.seedString, game.scoring.difficultyIndex)
    end
end

local function zoomBy(factor)
    local w, h = love.graphics.getDimensions()
    game.camera:zoomAt(factor, w / 2, h / 2)
end

-- Swap the skin: a new renderer for the same world, and remember the choice.
local function cycleTileset()
    Tileset.cycle()
    game.view = Tileset.newView(game.world)
    game.tileset = Tileset.current()
end

local function cycleSpeed()
    for i, v in ipairs(SIM_SPEEDS) do
        if v == simSpeed then simSpeed = SIM_SPEEDS[i % #SIM_SPEEDS + 1] break end
    end
    game.speed = simSpeed
end

-- Look at a tile: centre and zoom in on it, and mark it until the next tap
-- on the map.
local function lookAt(tile)
    if not tile then return end
    game.focus = { x = tile.x, y = tile.y }
    game.follow = false
    local cam = game.camera
    cam.scale = math.max(cam.scale, math.min(cam.maxScale, 3))
    cam:centerOn((tile.x - 0.5) * TILE_SIZE, (tile.y - 0.5) * TILE_SIZE)
end

local function openLog()
    state = 'log'
    love.mouse.setVisible(true)
end

-- The world stops; building, tools, panning and zooming carry on.
local function togglePause()
    game.paused = not game.paused
end

-- Gear menu buttons worth pressing again and again: the menu stays open
-- under them. The rest go somewhere or change the view, and close it.
local STAYS_OPEN = { speed = true, zoomin = true, zoomout = true, mute = true, sound = true }

-- b is the pressed button's rectangle, for a volume bar: where on it says how loud.
local function pressTopButton(id, x, b)
    local channel, step = id:match('^vol:(%a+):([%+%-])$')
    local barChannel = id:match('^volbar:(%a+)$')
    if id == 'gear' or id == 'values' or id == 'sound' then
        -- the folded buttons, values or mixer: open, or close again
        ui.dropdown = ui.dropdown ~= id and id or nil
    elseif channel then
        Audio.setVolume(channel, Audio.getVolume(channel) + (step == '+' and 0.1 or -0.1))
    elseif barChannel and b then
        Audio.setVolume(barChannel, (x - b.x) / b.w)
    elseif id == 'units' then openUnits()
    elseif id == 'pause' then togglePause()
    elseif id == 'log' then openLog()
    elseif id == 'fingers' then fingerDebug = not fingerDebug
    elseif id == 'speed' then cycleSpeed()
    elseif id == 'tiles' then cycleTileset()
    elseif id == 'follow' then toggleFollow()
    elseif id == 'zoomin' then zoomBy(1.25)
    elseif id == 'zoomout' then zoomBy(1 / 1.25)
    elseif id == 'mute' then Audio.toggleMute()
    elseif id == 'menu' then openMenu()
    elseif id == 'dev' then openSub('tools')
    elseif id == 'goal' then openGoal()
    end
    Audio.playSFX('click')
end

-- The first finger on the screen switches to the touch layout.
local function noteTouch()
    if ui.touch then return end
    ui.touch = true
    love.mouse.setVisible(true)
    ui:layout(love.graphics.getDimensions())
    if game and game.camera then
        game.camera:setView(love.graphics.getDimensions())
        game.camera:setInsets(TOP_BAR_H * ui.scale, BOTTOM_BAR_H * ui.scale)
        if isLevelMode() and not game.started then game.camera:fitWorld() end
    end
end

local function pointerPressed(x, y, button, istouch)
    if pinch then return end
    local vx, vy = ui:toVirtual(x, y)
    if state == 'title' then
        if button ~= 1 then return end
        local id = ui:titleButtonAt(vx, vy)
        if id == 'left' then
            titleMove(-1)
        elseif id == 'right' then
            titleMove(1)
        elseif id == 'diffLeft' then
            difficultyMove(-1)
        elseif id == 'diffRight' then
            difficultyMove(1)
        elseif id == 'seed' then
            title.editingSeed = not title.editingSeed
            love.keyboard.setTextInput(title.editingSeed)
        elseif id == 'mute' then
            Audio.toggleMute()
        elseif id and id:sub(1, 4) == 'key:' then
            -- the on-screen keyboard: phones will not raise their own for love.js
            local k = id:sub(5)
            if k == 'DEL' then
                title.seed = title.seed:sub(1, -2)
            elseif k == 'OK' then
                title.editingSeed = false
                if title.seed == '' then title.seed = DEFAULT_SEED end
            elseif #title.seed < 12 then
                title.seed = title.seed .. k
            end
            Audio.playSFX('click')
        elseif id == 'start' or not istouch then
            -- a click anywhere starts; a finger has to hit the box
            startFromTitle()
        end
        return
    elseif state == 'report' then
        if button == 1 then continueFromReport() end
        return
    elseif state == 'goal' then
        if button == 1 then closeGoal() end
        return
    end
    if button ~= 1 then return end
    local pb = ui:panelButtonAt(vx, vy)
    if pb then Audio.playSFX('click') end
    if pb == 'history' or pb == 'export' then
        openSub(pb)
        return
    end
    if state == 'gameover' then
        if pb == 'title' then goToTitle() end
        return
    elseif state == 'tools' then
        if pb == 'fingers' then fingerDebug = not fingerDebug
        elseif pb == 'back' then backTo(sub.toolsBack) end
        return
    elseif state == 'export' then
        if pb == 'save' then exportRun()
        elseif pb == 'typing' then love.keyboard.setTextInput(true)
        elseif pb == 'copy' and sub.saved then
            love.system.setClipboardText(sub.saved.json)
            sub.saved.message = 'Copied ' .. #sub.saved.json .. ' characters. Paste them into the run viewer.'
        elseif pb == 'download' and sub.saved then downloadRun()
        elseif pb == 'cancel' then closeSub()
        elseif pb == 'done' then closeExport() end
        return
    elseif state == 'history' then
        if pb == 'older' then sub.scroll = sub.scroll + math.max(1, sub.fit - 2)
        elseif pb == 'newer' then sub.scroll = math.max(0, sub.scroll - math.max(1, sub.fit - 2))
        elseif pb == 'close' then closeSub() end
        return
    elseif state == 'levelclear' then
        if pb == 'next' then nextLevelOrTitle() elseif pb == 'title' then goToTitle() end
        return
    elseif state == 'levelfailed' then
        if pb == 'retry' then newLevel(game.level.index, game.level.set, game.level.difficulty) elseif pb == 'title' then goToTitle() end
        return
    elseif state == 'annual' then
        if pb == 'title' then
            goToTitle()
        elseif pb == 'next' then
            game.scoring:startEndless()
            state = 'playing'
            hideCursor()
        end
        return
    elseif state == 'confirmquit' then
        if pb == 'yes' then
            goToTitle()
        elseif pb == 'restart' then
            restartGame()
        else
            state = 'playing'
            hideCursor()
        end
        return
    elseif state == 'log' then
        if pb and pb:sub(1, 5) == 'look:' then
            local e = game.log[tonumber(pb:sub(6))]
            state = 'playing'
            hideCursor()
            if e then lookAt(e.tile) end
        elseif pb == 'close' or not ui:insideLogPanel(vx, vy) then
            state = 'playing'
            hideCursor()
        end
        return
    elseif state == 'jobs' then
        if pb and pb:sub(1, 4) == 'job:' then
            pressJob(pb)
        elseif pb == 'jobprev' or pb == 'jobnext' then
            followNext(pb == 'jobnext' and 1 or -1)
        elseif pb == 'units' then
            openUnits()
        elseif pb == 'close' or not ui:insideJobPanel(vx, vy) then
            closeJobs()
        end
        return
    elseif state == 'units' then
        local w, what = ui:unitButtonAt(vx, vy)
        if w and what == 'jobs' then
            game.selectedWorker = w
            game.abilities:select(ABILITY_SELECT)
            openJobs()
        elseif w then
            game.selectedWorker = w
            game.follow = true
            game.abilities:select(ABILITY_SELECT)
            ui:toast('Following ' .. w.name)
            Audio.playSFX('click')
            closeUnits()
        elseif pb == 'close' or not ui:insideUnitPanel(vx, vy) then
            closeUnits()
        end
        return
    end
    -- playing
    if button == 2 then
        game.dragging = true
        return
    end
    if button ~= 1 then return end
    if ui.dropdown then
        -- an open dropdown takes the press: a button in it, or a press
        -- anywhere else just closes it
        local id, b = ui:dropdownAt(vx, vy)
        if id == 'inside' then return end
        if id then
            if not (STAYS_OPEN[id] or id:find('^vol')) then ui.dropdown = nil end
            pressTopButton(id, vx, b)
            return
        end
        local top = vy < TOP_BAR_H and ui:topButtonAt(vx, vy)
        if not (top == ui.dropdown) then ui.dropdown = nil end
        if not top then return end
    end
    if vy < TOP_BAR_H then
        local id = ui:topButtonAt(vx, vy)
        if id then pressTopButton(id) end
        return
    end
    if ui:restartButtonAt(vx, vy) then
        restartGame()
        return
    end
    local nav = ui:followNavAt(vx, vy)
    if nav then
        followNext(nav)
        Audio.playSFX('click')
        return
    end
    if ui:alertLogAt(vx, vy) then
        openLog()
        return
    end
    if ui:followButtonAt(vx, vy) then
        toggleFollow()
        Audio.playSFX('click')
        return
    end
    -- an announcement with a place: look at it
    local alert = ui:alertAt(vx, vy)
    if alert then
        if alert.tile then lookAt(alert.tile) else openLog() end
        return
    end
    if ui:jobsButtonAt(vx, vy) then
        openJobs()
        return
    end
    if vy > ui.vh - BOTTOM_BAR_H then
        local tool = ui:buttonAt(vx, vy)
        if tool then
            game.abilities:select(tool)
            Audio.playSFX('click')
        end
        return
    end
    local tile = game.camera:toTile(x, y)
    local tool = game.abilities.selected
    game.focus = nil -- a tap on the map lets go of the spot being looked at
    if DEBUG or CLICK_DEBUG then
        local t = game.world:get(tile.x, tile.y)
        print(string.format('click screen %d,%d -> tile %d,%d type=%s cam=%.1f,%.1f scale=%.2f win=%dx%d',
            x, y, tile.x, tile.y, t and t.type or 'nil', game.camera.x, game.camera.y, game.camera.scale,
            love.graphics.getWidth(), love.graphics.getHeight()))
    end
    if tool == ABILITY_SELECT then
        -- a tap selects, a drag pans; decided on release
        game.panStart = { x = x, y = y, moved = false, tile = tile }
    else
        -- every other tool acts on release, so a second finger (a pinch)
        -- can still call it off
        game.lineStart = tile
        game.lineCost = nil
    end
end

local function pointerReleased(x, y, button)
    if state ~= 'playing' then return end
    if button == 2 then
        game.dragging = false
    elseif button == 1 and game.panStart then
        if not game.panStart.moved then game.selectedWorker = workerAt(game.panStart.tile) end
        game.panStart = nil
    elseif button == 1 and game.lineStart then
        if not ui:isOverBars(ui:toVirtual(x, y)) then
            local tile = game.camera:toTile(x, y)
            local ok, why = game.abilities:useDrag(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
            if why then ui:toast(why) end
        end
        game.lineStart = nil
        game.lineCost = nil
    end
end

local function pointerMoved(x, y, dx, dy)
    if state ~= 'playing' or pinch then return end
    if game.dragging then
        game.follow = false
        game.camera:pan(-dx, -dy)
    elseif game.panStart then
        local p = game.panStart
        if not p.moved and math.abs(x - p.x) + math.abs(y - p.y) > 10 then p.moved = true end
        if p.moved then
            game.follow = false
            game.camera:pan(-dx, -dy)
        end
    end
end

-- A mouse made up from a finger is ignored: the touch events do that work.
local function realMouse(istouch)
    return not istouch and love.timer.getTime() - lastTouchAt > 1
end

function love.mousepressed(x, y, button, istouch)
    if istouch then noteTouch() end
    if realMouse(istouch) then pointerPressed(x, y, button, false) end
end

function love.mousereleased(x, y, button, istouch)
    if realMouse(istouch) then pointerReleased(x, y, button) end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if realMouse(istouch) then pointerMoved(x, y, dx, dy) end
end

-- Two fingers: pinch to zoom around the midpoint and drag to pan. One finger
-- arrives as ordinary mouse events, so taps and drags need nothing special.
local function pinchState()
    local ids = {}
    for id in pairs(touches) do ids[#ids + 1] = id end
    if #ids < 2 then return nil end
    local a, b = touches[ids[1]], touches[ids[2]]
    local dist = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    return { dist = math.max(dist, 1), mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2 }
end

-- The lowest finger number nobody is using, for the FINGERS debug view.
local function freeFingerNumber()
    local used = {}
    for _, t in pairs(touches) do if t.n then used[t.n] = true end end
    local n = 1
    while used[n] do n = n + 1 end
    return n
end

function love.touchpressed(id, x, y)
    noteTouch()
    lastTouchAt = love.timer.getTime()
    touches[id] = { x = x, y = y, n = freeFingerNumber(), seen = debugClock }
    touchCount = 0
    for _ in pairs(touches) do touchCount = touchCount + 1 end
    if touchCount == 1 then
        primary = id
        pointerX, pointerY = x, y
        pointerPressed(x, y, 1, true)
    elseif state == 'playing' then
        -- a second finger: a pinch, and whatever the first began is off
        primary = nil
        pinch = pinchState()
        game.panStart = nil
        game.lineStart = nil
        game.lineCost = nil
        game.dragging = false
    else
        primary = nil
    end
end

function love.touchmoved(id, x, y)
    if not touches[id] then return end
    lastTouchAt = love.timer.getTime()
    touches[id].x, touches[id].y, touches[id].seen = x, y, debugClock
    if id == primary then
        local dx, dy = x - pointerX, y - pointerY
        pointerX, pointerY = x, y
        pointerMoved(x, y, dx, dy)
    end
    if pinch and state == 'playing' then
        local now = pinchState()
        if now then
            game.follow = false
            game.camera:zoomAt(now.dist / pinch.dist, now.mx, now.my)
            game.camera:pan(pinch.mx - now.mx, pinch.my - now.my)
            pinch = now
        end
    end
end

function love.touchreleased(id, x, y)
    lastTouchAt = love.timer.getTime()
    touches[id] = nil
    if id == primary then
        primary = nil
        pointerX, pointerY = x or pointerX, y or pointerY
        pointerReleased(pointerX, pointerY, 1)
    end
    touchCount = 0
    for _ in pairs(touches) do touchCount = touchCount + 1 end
    if touchCount < 2 then pinch = nil end
end

function love.wheelmoved(_, y)
    if state ~= 'playing' or y == 0 then return end
    local mx, my = pointerPosition()
    game.camera:zoomAt(y > 0 and 1.15 or 1 / 1.15, mx, my)
end

function love.keypressed(key)
    if key == 'f3' then
        fingerDebug = not fingerDebug
        return
    end
    if key == 'f11' and not isWeb() then
        love.window.setFullscreen(not love.window.getFullscreen())
        return
    end
    if state == 'export' and not sub.saved then
        if key == 'return' or key == 'kpenter' then exportRun()
        elseif key == 'escape' then closeSub()
        elseif key == 'backspace' then sub.text = sub.text:sub(1, -2)
        elseif key == 'space' then
            -- love.js sends no text for the space bar; on the desktop the
            -- text that follows this key is skipped instead
            sub.text = (sub.text .. ' '):sub(1, STATS_BLURB_MAX)
            sub.spaced = true
        end
        return
    end
    if key == 'm' and not (state == 'title' and title.editingSeed) then
        Audio.toggleMute()
        return
    end
    if state == 'title' then
        if title.editingSeed then
            if key == 'return' or key == 'kpenter' or key == 'escape' then
                title.editingSeed = false
            elseif key == 'backspace' then
                title.seed = title.seed:sub(1, -2)
            end
            return
        end
        if key == 'return' or key == 'kpenter' or key == 'space' then
            startFromTitle()
        elseif key == 'left' or key == 'a' then
            titleMove(-1)
        elseif key == 'right' or key == 'd' then
            titleMove(1)
        elseif key == 'up' or key == 'w' then
            difficultyMove(-1)
        elseif key == 'down' then
            difficultyMove(1)
        elseif key == 's' and title.options[title.option].kind == 'free' then
            title.editingSeed = true
            title.swallowText = true -- the S that opened the field is not part of the seed
        elseif key == 'escape' and not isWeb() then
            love.event.quit()
        end
    elseif state == 'playing' then
        local n = tonumber(key)
        if n and ABILITY_ORDER[n] then
            game.abilities:select(ABILITY_ORDER[n])
            Audio.playSFX('click')
        elseif key == 'f' then
            toggleFollow()
        elseif key == ']' or key == '[' then
            followNext(key == ']' and 1 or -1)
            Audio.playSFX('click')
        elseif key == 'space' or key == 'p' then
            togglePause()
            Audio.playSFX('click')
        elseif key == 'tab' then
            cycleSpeed()
            Audio.playSFX('click')
        elseif key == 't' then
            cycleTileset()
            Audio.playSFX('click')
        elseif key == 'u' then
            openUnits()
        elseif key == 'j' then
            openJobs()
        elseif key == 'g' then
            openGoal()
        elseif key == 'l' then
            openLog()
        elseif key == 'r' then
            if game.suggestRestart then restartGame() else openMenu() end
        elseif key == '=' or key == '+' or key == 'kp+' then
            zoomBy(1.25)
        elseif key == '-' or key == 'kp-' then
            zoomBy(1 / 1.25)
        elseif key == 'escape' then
            openMenu()
        end
    elseif state == 'log' then
        if key == 'l' or key == 'escape' then state = 'playing'; hideCursor() end
    elseif state == 'units' then
        if key == 'u' or key == 'escape' then closeUnits() end
    elseif state == 'jobs' then
        if key == 'j' or key == 'escape' then
            closeJobs()
        elseif key == 'u' then
            openUnits()
        elseif key == ']' or key == '[' then
            followNext(key == ']' and 1 or -1)
            Audio.playSFX('click')
        end
    elseif state == 'confirmquit' then
        if key == 'y' or key == 'return' or key == 'kpenter' then
            goToTitle()
        elseif key == 'r' then
            restartGame()
        else
            state = 'playing'
            hideCursor()
        end
    elseif state == 'report' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            continueFromReport()
        end
    elseif state == 'gameover' then
        if key == 'return' or key == 'kpenter' or key == 'space' or key == 'escape' then
            goToTitle()
        elseif key == 'h' then openSub('history')
        elseif key == 'e' then openSub('export') end
    elseif state == 'export' then
        if key == 'return' or key == 'kpenter' or key == 'escape' then closeExport() end
    elseif state == 'tools' then
        if key == 'escape' then backTo(sub.toolsBack) end
    elseif state == 'history' then
        if key == 'up' then sub.scroll = sub.scroll + 1
        elseif key == 'down' then sub.scroll = math.max(0, sub.scroll - 1)
        elseif key == 'escape' or key == 'h' or key == 'return' then closeSub() end
    elseif state == 'goal' then
        closeGoal()
    elseif state == 'levelclear' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            nextLevelOrTitle()
        elseif key == 'escape' then
            goToTitle()
        elseif key == 'h' then openSub('history')
        elseif key == 'e' then openSub('export')
        end
    elseif state == 'levelfailed' then
        if key == 'return' or key == 'kpenter' or key == 'space' or key == 'r' then
            newLevel(game.level.index, game.level.set, game.level.difficulty)
        elseif key == 'escape' then
            goToTitle()
        elseif key == 'h' then openSub('history')
        elseif key == 'e' then openSub('export')
        end
    elseif state == 'annual' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            game.scoring:startEndless()
            state = 'playing'
            hideCursor()
        elseif key == 't' or key == 'escape' then
            goToTitle()
        elseif key == 'h' then openSub('history')
        elseif key == 'e' then openSub('export')
        end
    end
end

function love.textinput(text)
    if title.swallowText then
        title.swallowText = false
        return
    end
    if state == 'export' and not sub.saved then
        -- printable ASCII only: the C64 face has nothing else
        if text == ' ' and sub.spaced then sub.spaced = false return end
        sub.spaced = false
        text = text:gsub('[^\32-\126]', '')
        sub.text = (sub.text .. text):sub(1, STATS_BLURB_MAX)
        return
    end
    if state == 'title' and title.editingSeed and #title.seed < 12 and text:match('^[%w]$') then
        title.seed = title.seed .. text
    end
end

-- tst/ui_overflow_test.lua drives every screen through these; the game never sets TEST_HOOKS
if TEST_HOOKS then
    TEST_HOOKS.main = {
        ui = function() return ui end,
        game = function() return game end,
        state = function() return state end,
        setState = function(s) state = s end,
        title = title,
        newLevel = newLevel,
        newGame = newGame,
        levelClear = levelClear,
        finishGame = finishGame,
        closeQuarter = closeQuarter,
        closeGoal = closeGoal,
        goToTitle = goToTitle,
        buildTitleOptions = buildTitleOptions,
        announce = announce,
        lookAt = lookAt,
        openSub = openSub,
        exportRun = exportRun,
        sub = sub,
        openJobs = function() openJobs() end,
        pressJob = function(id) pressJob(id) end,
    }
end
