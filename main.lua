-- Morphis. A small band settling the harsh wilds. You shape the land; they look after themselves.
require('src.constants')
local Util = require('src.util')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Worker = require('src.worker')
local Scoring = require('src.scoring')
local Abilities = require('src.abilities')
local Highscore = require('src.highscore')
local Campaign = require('src.campaign')
local Camera = require('src.camera')
local View = require('src.view')
local UI = require('src.ui')
local Effects = require('src.effects')
local Audio = require('src.audio')

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
local reportTimer = 0
local musicStarted = false
local PAN_SPEED = 700

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

local NODE_WORDS = { bush = 'bush', tree = 'tree', ore = 'gold' }

local function onComplain(worker, reason, node)
    local where = node and (NODE_WORDS[node.kind] .. ' at ' .. node.x .. ',' .. node.y) or 'somewhere'
    local text
    if reason == 'hungry' then
        text = worker.name .. ' is hungry and the ' .. where .. ' is walled off'
    elseif reason == 'slow' then
        text = worker.name .. ' gave up walking to the ' .. where
    else
        text = worker.name .. " can't reach the " .. where
    end
    ui:alert(text, node and { x = node.x, y = node.y } or nil)
    Audio.playSFX('complain')
end

local function onWorkerEvent(worker, name, data)
    if name == 'eat' then Audio.playSFX('eat')
    elseif name == 'deliver' then Audio.playSFX('deliver')
    elseif name == 'pickup' then Audio.playSFX('click')
    elseif name == 'mined' then Audio.playSFX('dig')
    elseif name == 'built' then Audio.playSFX('hire')
    elseif name == 'break' then Audio.playSFX('settled')
    elseif name == 'work' then Audio.playSFX(data == 'ore' and 'dig' or (data == 'tree' and 'line' or 'click'))
    elseif name == 'lowmorale' then
        ui:alert(worker.name .. ' is fed up and close to leaving the band.')
    elseif name == 'quit' then
        Audio.playSFX('quit')
        if data == 'morale' then
            ui:alert(worker.name .. ' left the band. Too many hardships, too little care.')
        else
            ui:alert(worker.name .. ' starved and wandered off into the wilds.')
        end
        if game.mode == 'level' and (state == 'playing' or state == 'units') then
            game.failReason = worker.name .. (data == 'morale' and ' had enough and left.' or ' starved.')
            state = 'levelfailed'
            love.mouse.setVisible(true)
        end
    end
end

local function hire(n)
    local spots = game.world:spawnTiles(3)
    if #spots == 0 then spots = { { x = game.world.breakroom.x, y = game.world.breakroom.y } } end
    for _ = 1, n do
        game.hired = game.hired + 1
        local spot = spots[(game.hired - 1) % #spots + 1]
        local role = HIRE_ORDER[(game.hired - 1) % #HIRE_ORDER + 1]
        local sheets = ROLES[role].sheets
        game.roleHires[role] = (game.roleHires[role] or 0) + 1
        local worker = Worker.new(game.world, game.jobs, game.scoring, game.rng, {
            x = spot.x, y = spot.y,
            role = role,
            sheet = sheets[(game.roleHires[role] - 1) % #sheets + 1],
            name = MORPHI_NAMES[(game.hired - 1) % #MORPHI_NAMES + 1],
            drain = game.scoring.drain,
            hunger = STARTING_HUNGER,
            onComplain = onComplain,
            onEvent = onWorkerEvent,
        })
        table.insert(game.workers, worker)
    end
end

local function onReady(node)
    game.jobs:postNode(node)
end

local function onEffect(name, data)
    if name == 'mine' then
        Audio.playSFX('click')
        ui:toast(data.count .. ' tile' .. (data.count == 1 and '' or 's') .. ' marked for mining')
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
    game.world.stock = { logs = STARTING_STOCK.logs, gold = STARTING_STOCK.gold }
    game.world:spawnAllNodes(NODES_INITIAL)
    -- everything standing at the start is already workable
    for _, node in ipairs(game.world.nodes) do
        if node.ready then game.jobs:postNode(node) end
    end
    game.workers = {}
    game.hired = 0
    game.roleHires = {}
    game.clock = 0
    game.staffCount = 0
    game.averageHunger = 100
    game.abilities = Abilities.new(game.world, game.jobs, onEffect)
    game.view = View.new(game.world)
    game.camera = Camera.new(game.world.w, game.world.h, love.graphics.getDimensions())
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
    hire(DIFFICULTIES[difficultyIndex].workers)
    ui:alert('Mark a free FLOOR spot (or a BIN, 1 log, holds 4) so foragers can put food down. BRIDGE the rivers to reach the far banks.')
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
    game.mode = set == 'arcade' and 'arcade' or 'level'
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
    game.roleHires = {}
    game.clock = 0
    game.staffCount = #run.specs
    game.averageHunger = run.def.hunger or HUNGER_MAX
    game.abilities = Abilities.new(game.world, game.jobs, onEffect)
    game.view = View.new(game.world)
    game.camera = Camera.new(game.world.w, game.world.h, love.graphics.getDimensions())
    game.camera:fitWorld((TOP_BAR_H + BOTTOM_BAR_H) * ui.scale)
    game.selectedWorker = nil
    game.follow = false
    game.lineStart = nil
    game.dragging = false
    game.report = nil
    game.highScore = 0
    game.isNewHigh = false
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
    lv.stars = Campaign.stars(spent, lv.def.par)
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
    for _, node in ipairs(game.world:spawnAllNodes(NODES_PER_QUARTER)) do
        if node.ready then game.jobs:postNode(node) end
    end
    for _, w in ipairs(game.workers) do w.drain = game.scoring.drain end
    if game.report.hires > 0 then
        hire(game.report.hires)
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
        ui:alert(game.scoring:seasonLabel() .. ' begins. ' .. game.report.hires .. ' migrant' .. (game.report.hires == 1 and '' or 's') .. ' joined the band.')
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
    love.keyboard.setKeyRepeat(true)
    buildTitleOptions()
    -- start on the furthest unlocked arcade level
    title.option = math.min(levelsUnlocked('arcade'), Campaign.count('arcade'))
end

function love.resize(w, h)
    ui:layout(w, h)
    if game and game.camera then
        game.camera:setView(w, h)
        if isLevelMode() and not game.started then game.camera:fitWorld((TOP_BAR_H + BOTTOM_BAR_H) * ui.scale) end
    end
end


local function updatePlaying(dt)
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

function love.update(dt)
    dt = math.min(dt, 0.1)
    Audio.update(dt)
    if state == 'playing' or state == 'units' then
        updatePlaying(dt)
        ui:update(dt)
    elseif state == 'report' then
        reportTimer = reportTimer + dt
        if reportTimer > 15 then continueFromReport() end
    end
    -- 'confirmquit' and 'goal' are pauses: nothing updates
end

local function drawWorld()
    local cam = game.camera
    game.view:rebuildCanvas() -- before the camera transform, see View:rebuildCanvas
    -- beyond the map: dark ground, not a black hole
    love.graphics.setColor(0.11, 0.13, 0.09, 1)
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
    -- cursor preview
    if state == 'playing' then
        local mx, my = love.mouse.getPosition()
        if not ui:isOverBars(mx, my) then
            local tile = cam:toTile(mx, my)
            local tool = game.abilities.selected
            if tool == ABILITY_MINE and game.lineStart then
                local lx, hx = math.min(game.lineStart.x, tile.x), math.max(game.lineStart.x, tile.x)
                local ly, hy = math.min(game.lineStart.y, tile.y), math.max(game.lineStart.y, tile.y)
                for x = lx, hx do
                    for y = ly, hy do
                        local t = game.world:get(x, y)
                        local minable = t and (t.type == TILE_STONE or t.type == TILE_SNOW)
                        game.view:drawTileFill(x, y, minable and { 1, 0.6, 0.2, 0.45 } or { 1, 1, 1, 0.12 })
                    end
                end
            elseif tool == ABILITY_BRIDGE and game.lineStart then
                local tiles, cost = game.abilities:lineQuote(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
                for _, p in ipairs(tiles) do
                    local t = game.world:get(p.x, p.y)
                    local color = (t and t.type == TILE_WATER) and { 0.9, 0.7, 0.3, 0.55 } or { 1, 1, 1, 0.15 }
                    game.view:drawTileFill(p.x, p.y, color)
                end
                game.lineCost = cost
            else
                game.view:drawTileOutline(tile.x, tile.y, { 1, 1, 1, 0.8 })
            end
        end
    end
    game.view:drawWorkers(game.workers, game.clock, game.selectedWorker)
    Effects.draw()
    cam:reset()
end

function love.draw()
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
        ui:drawGameOver(game.scoring, game.highScore, game.isNewHigh)
    elseif state == 'annual' then
        ui:drawAnnual(game.scoring, game.highScore, game.isNewHigh)
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
    end
    ui:endScaled()
    if state == 'playing' then
        local mx, my = love.mouse.getPosition()
        if game.lineStart and game.lineCost and game.abilities.selected == ABILITY_BRIDGE then
            love.graphics.setFont(ui.fonts.small)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print('bridge: ' .. game.lineCost .. ' logs', mx + 18, my + 18)
        end
        ui:drawCursor(game.abilities.selected, mx, my)
    end
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

local function openMenu()
    state = 'confirmquit'
    love.mouse.setVisible(true)
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

local function pressTopButton(id)
    if id == 'units' then openUnits()
    elseif id == 'follow' then toggleFollow()
    elseif id == 'zoomin' then zoomBy(1.25)
    elseif id == 'zoomout' then zoomBy(1 / 1.25)
    elseif id == 'mute' then Audio.toggleMute()
    elseif id == 'menu' then openMenu()
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
        if isLevelMode() and not game.started then game.camera:fitWorld((TOP_BAR_H + BOTTOM_BAR_H) * ui.scale) end
    end
end

function love.mousepressed(x, y, button, istouch)
    if istouch then noteTouch() end
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
        elseif id == 'start' or not istouch then
            -- a click anywhere starts; a finger has to hit the box
            startFromTitle()
        end
        return
    elseif state == 'report' then
        if button == 1 then continueFromReport() end
        return
    elseif state == 'gameover' then
        if button == 1 then goToTitle() end
        return
    elseif state == 'goal' then
        if button == 1 then closeGoal() end
        return
    end
    if button ~= 1 then return end
    local pb = ui:panelButtonAt(vx, vy)
    if pb then Audio.playSFX('click') end
    if state == 'levelclear' then
        if pb == 'next' then nextLevelOrTitle() elseif pb == 'title' then goToTitle() end
        return
    elseif state == 'levelfailed' then
        if pb == 'retry' then newLevel(game.level.index, game.level.set, game.level.difficulty) elseif pb == 'title' then goToTitle() end
        return
    elseif state == 'annual' then
        if pb == 'title' then
            goToTitle()
        else
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
    elseif state == 'units' then
        local w = ui:unitButtonAt(vx, vy)
        if w then
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
    if vy < TOP_BAR_H then
        local id = ui:topButtonAt(vx, vy)
        if id then pressTopButton(id) end
        return
    end
    if ui:restartButtonAt(vx, vy) then
        restartGame()
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
    if DEBUG or CLICK_DEBUG then
        local t = game.world:get(tile.x, tile.y)
        print(string.format('click screen %d,%d -> tile %d,%d type=%s cam=%.1f,%.1f scale=%.2f win=%dx%d',
            x, y, tile.x, tile.y, t and t.type or 'nil', game.camera.x, game.camera.y, game.camera.scale,
            love.graphics.getWidth(), love.graphics.getHeight()))
    end
    if tool == ABILITY_SELECT then
        -- a tap selects, a drag pans; decided on release
        game.panStart = { x = x, y = y, moved = false, tile = tile }
    elseif tool == ABILITY_BRIDGE or tool == ABILITY_MINE then
        game.lineStart = tile
        game.lineCost = nil
    else
        local ok, why = game.abilities:use(tile.x, tile.y)
        if not ok and why then ui:toast(why) end
    end
end

function love.mousereleased(x, y, button)
    if state ~= 'playing' then return end
    if button == 2 then
        game.dragging = false
    elseif button == 1 and game.panStart then
        if not game.panStart.moved then game.selectedWorker = workerAt(game.panStart.tile) end
        game.panStart = nil
    elseif button == 1 and game.lineStart then
        if not ui:isOverBars(ui:toVirtual(x, y)) then
            local tile = game.camera:toTile(x, y)
            local ok, why
            if game.abilities.selected == ABILITY_MINE then
                ok, why = game.abilities:designateMine(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
            else
                ok, why = game.abilities:useLine(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
            end
            if not ok and why then ui:toast(why) end
        end
        game.lineStart = nil
        game.lineCost = nil
    end
end

function love.mousemoved(x, y, dx, dy)
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

function love.touchpressed(id, x, y)
    noteTouch()
    touches[id] = { x = x, y = y }
    touchCount = touchCount + 1
    if touchCount >= 2 and state == 'playing' then
        pinch = pinchState()
        game.panStart = nil
        game.lineStart = nil
        game.lineCost = nil
        game.dragging = false
    end
end

function love.touchmoved(id, x, y)
    if not touches[id] then return end
    touches[id].x, touches[id].y = x, y
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

function love.touchreleased(id)
    if touches[id] then
        touches[id] = nil
        touchCount = math.max(0, touchCount - 1)
    end
    if touchCount < 2 then pinch = nil end
end

function love.wheelmoved(_, y)
    if state ~= 'playing' or y == 0 then return end
    local mx, my = love.mouse.getPosition()
    game.camera:zoomAt(y > 0 and 1.15 or 1 / 1.15, mx, my)
end

function love.keypressed(key)
    if key == 'f11' and not isWeb() then
        love.window.setFullscreen(not love.window.getFullscreen())
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
        elseif key == 'u' then
            openUnits()
        elseif key == 'g' then
            openGoal()
        elseif key == 'r' then
            if game.suggestRestart then restartGame() else openMenu() end
        elseif key == '=' or key == '+' or key == 'kp+' then
            zoomBy(1.25)
        elseif key == '-' or key == 'kp-' then
            zoomBy(1 / 1.25)
        elseif key == 'escape' then
            openMenu()
        end
    elseif state == 'units' then
        if key == 'u' or key == 'escape' then closeUnits() end
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
        end
    elseif state == 'goal' then
        closeGoal()
    elseif state == 'levelclear' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            nextLevelOrTitle()
        elseif key == 'escape' then
            goToTitle()
        end
    elseif state == 'levelfailed' then
        if key == 'return' or key == 'kpenter' or key == 'space' or key == 'r' then
            newLevel(game.level.index, game.level.set, game.level.difficulty)
        elseif key == 'escape' then
            goToTitle()
        end
    elseif state == 'annual' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            game.scoring:startEndless()
            state = 'playing'
            hideCursor()
        elseif key == 't' or key == 'escape' then
            goToTitle()
        end
    end
end

function love.textinput(text)
    if state == 'title' and title.editingSeed and #title.seed < 12 and text:match('^[%w]$') then
        title.seed = title.seed .. text
    end
end
