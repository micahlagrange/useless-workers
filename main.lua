-- Human Resources. Control the environment, not the employees.
require('src.constants')
local Util = require('src.util')
local Rng = require('src.rng')
local World = require('src.world')
local Jobs = require('src.jobs')
local Worker = require('src.worker')
local Scoring = require('src.scoring')
local Abilities = require('src.abilities')
local Highscore = require('src.highscore')
local Camera = require('src.camera')
local View = require('src.view')
local UI = require('src.ui')
local Effects = require('src.effects')
local Audio = require('src.audio')

love.graphics.setDefaultFilter('nearest', 'nearest')

local state = 'title'
local ui
local game = {}
local title = { difficultyIndex = DEFAULT_DIFFICULTY, seed = DEFAULT_SEED, editingSeed = false }
local reportTimer = 0
local musicStarted = false
local PAN_SPEED = 700

local function isWeb()
    return love.system.getOS() == 'Web'
end

local function startMusic()
    if not musicStarted then
        Audio.playBGM('theme')
        musicStarted = true
    end
end

-- Game setup ---------------------------------------------------------------

local function tintFor(index)
    local i = (index - 1) % #WORKER_TINTS + 1
    return Util.hexToRgb(WORKER_TINTS[i]), WORKER_TINT_NAMES[i]
end

local function onComplain(worker, reason, x, y)
    local text
    if reason == 'hungry' then
        text = worker.name .. ' is hungry and the fruit at ' .. x .. ',' .. y .. ' is walled off'
    elseif reason == 'slow' then
        text = worker.name .. ' gave up walking to ' .. (x or '?') .. ',' .. (y or '?')
    else
        text = worker.name .. " can't reach the fruit at " .. x .. ',' .. y
    end
    ui:alert(text, x and { x = x, y = y } or nil)
    Audio.playSFX('complain')
end

local function onWorkerEvent(worker, name)
    if name == 'eat' then Audio.playSFX('eat')
    elseif name == 'deliver' then Audio.playSFX('deliver')
    elseif name == 'quit' then
        Audio.playSFX('quit')
        ui:alert(worker.name .. ' quit. Starved on the job.')
    end
end

local function hire(n)
    local spots = game.world:spawnTiles(3)
    if #spots == 0 then spots = { { x = game.world.breakroom.x, y = game.world.breakroom.y } } end
    for _ = 1, n do
        game.hired = game.hired + 1
        local spot = spots[(game.hired - 1) % #spots + 1]
        local tint, tintName = tintFor(game.hired)
        local worker = Worker.new(game.world, game.jobs, game.scoring, game.rng, {
            x = spot.x, y = spot.y,
            name = WORKER_NAMES[(game.hired - 1) % #WORKER_NAMES + 1],
            tint = tint, tintName = tintName,
            drain = game.scoring.drain,
            onComplain = onComplain,
            onEvent = onWorkerEvent,
        })
        table.insert(game.workers, worker)
    end
end

local function onRipe(tree)
    game.jobs:postHarvest(tree, tree.memo)
    tree.memo = false
end

local function onEffect(name, data)
    if name == 'dig' then
        Audio.playSFX('dig')
    elseif name == 'explode' then
        Audio.playSFX('explode')
        Effects.shake(0.35, 5)
        local c = Util.tileCenter(data.x, data.y)
        Effects.explosion(c.x, c.y, TILE_SIZE * (data.radius * 2 + 1.5))
    elseif name == 'line' then
        Audio.playSFX('line')
    elseif name == 'memo' then
        Audio.playSFX('memo')
        ui:toast('Memo sent to ' .. data.trees .. ' tree' .. (data.trees == 1 and '' or 's'))
    end
end

local function newGame(seedString, difficultyIndex)
    game = {}
    game.seedString = seedString
    game.seedNumber = Rng.seedToNumber(seedString)
    game.rng = Rng.new(game.seedNumber)
    game.scoring = Scoring.new(difficultyIndex)
    game.world = World.generate(game.seedNumber, game.rng)
    game.jobs = Jobs.new()
    game.world:spawnTrees(TREES_INITIAL)
    game.workers = {}
    game.hired = 0
    game.clock = 0
    game.staffCount = 0
    game.averageHunger = 100
    game.abilities = Abilities.new(game.world, game.scoring, game.jobs, onEffect)
    game.view = View.new(game.world)
    game.camera = Camera.new(game.world.w, game.world.h, WINDOW_WIDTH, WINDOW_HEIGHT)
    game.camera.scale = 2
    game.camera:centerOn(game.world.breakroom.cx, game.world.breakroom.cy)
    game.selectedWorker = nil
    game.lineStart = nil
    game.dragging = false
    game.report = nil
    game.highScore = Highscore.load(difficultyIndex)
    game.isNewHigh = false
    Effects.clear()
    ui:clear()
    hire(DIFFICULTIES[difficultyIndex].workers)
    ui:alert('Keep them fed. Dig, blast and bridge so they can reach the fruit.')
    state = 'playing'
    love.mouse.setVisible(false)
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
    game.world:spawnTrees(TREES_PER_QUARTER)
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
        love.mouse.setVisible(false)
        ui:alert('Q' .. game.scoring.quarter .. ' begins. ' .. game.report.hires .. ' new hire' .. (game.report.hires == 1 and '' or 's') .. ' arrived.')
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
end

-- LOVE callbacks -----------------------------------------------------------

function love.load()
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
    ui = UI.new()
    love.keyboard.setKeyRepeat(true)
end

local function updatePlaying(dt)
    game.clock = game.clock + dt
    game.jobs:update(dt)
    game.world:update(dt, onRipe)
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
    if count == 0 then
        finishGame('gameover')
        return
    end
    if game.scoring:update(dt, avg) then
        closeQuarter()
        return
    end
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') or love.keyboard.isDown('up') then dy = dy - 1 end
    if love.keyboard.isDown('s') or love.keyboard.isDown('down') then dy = dy + 1 end
    if love.keyboard.isDown('a') or love.keyboard.isDown('left') then dx = dx - 1 end
    if love.keyboard.isDown('d') or love.keyboard.isDown('right') then dx = dx + 1 end
    if dx ~= 0 or dy ~= 0 then
        game.camera:pan(dx * PAN_SPEED * dt, dy * PAN_SPEED * dt)
    end
    Effects.update(dt)
end

function love.update(dt)
    dt = math.min(dt, 0.1)
    Audio.update(dt)
    if state == 'playing' then
        updatePlaying(dt)
        ui:update(dt)
    elseif state == 'report' then
        reportTimer = reportTimer + dt
        if reportTimer > 15 then continueFromReport() end
    end
end

local function drawWorld()
    local cam = game.camera
    cam:apply()
    Effects.applyShake()
    game.view:drawWorld()
    game.view:drawBreakroom()
    game.view:drawTrees(game.clock)
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
            if tool == ABILITY_EXPLODE then
                local r = game.abilities.explodeRadius
                game.view:drawTileOutline(tile.x - r, tile.y - r, { 1, 0.6, 0.2, 0.9 }, r * 2 + 1)
            elseif tool == ABILITY_LINE and game.lineStart then
                local tiles, cost = game.abilities:lineQuote(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
                for _, p in ipairs(tiles) do
                    local t = game.world:get(p.x, p.y)
                    local color = (t and t.type == TILE_WATER) and { 0.9, 0.7, 0.3, 0.55 } or { 1, 1, 1, 0.15 }
                    game.view:drawTileFill(p.x, p.y, color)
                end
                game.lineCost = cost
            elseif tool == ABILITY_MEMO then
                game.view:drawTileOutline(tile.x - MEMO_RADIUS, tile.y - MEMO_RADIUS, { 1, 0.95, 0.5, 0.6 }, MEMO_RADIUS * 2 + 1)
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
        ui:drawTitle(title, Highscore.load(title.difficultyIndex))
        return
    end
    drawWorld()
    ui:drawHUD(game)
    if state == 'report' then
        ui:drawReport(game.report, game.scoring)
    elseif state == 'gameover' then
        ui:drawGameOver(game.scoring, game.highScore, game.isNewHigh)
    elseif state == 'annual' then
        ui:drawAnnual(game.scoring, game.highScore, game.isNewHigh)
    elseif state == 'playing' then
        local mx, my = love.mouse.getPosition()
        if game.lineStart and game.lineCost then
            love.graphics.setFont(ui.fonts.small)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print('bridge cost ' .. game.lineCost, mx + 18, my + 18)
        end
        ui:drawCursor(game.abilities.selected, mx, my)
    end
end

-- Input --------------------------------------------------------------------

local function startFromTitle()
    startMusic()
    title.editingSeed = false
    if title.seed == '' then title.seed = DEFAULT_SEED end
    newGame(title.seed, title.difficultyIndex)
end

function love.mousepressed(x, y, button)
    if state == 'title' then
        if button == 1 then startFromTitle() end
        return
    elseif state == 'report' then
        if button == 1 then continueFromReport() end
        return
    elseif state == 'gameover' then
        if button == 1 then goToTitle() end
        return
    elseif state == 'annual' then
        if button == 1 then
            game.scoring:startEndless()
            state = 'playing'
            love.mouse.setVisible(false)
        end
        return
    end
    -- playing
    if button == 2 then
        game.dragging = true
        return
    end
    if button ~= 1 then return end
    if y < TOP_BAR_H then return end
    if y > WINDOW_HEIGHT - BOTTOM_BAR_H then
        local tool = ui:buttonAt(x, y)
        if tool then
            game.abilities:select(tool)
            Audio.playSFX('click')
        end
        return
    end
    local tile = game.camera:toTile(x, y)
    local tool = game.abilities.selected
    if tool == ABILITY_SELECT then
        game.selectedWorker = workerAt(tile)
    elseif tool == ABILITY_LINE then
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
    elseif button == 1 and game.lineStart then
        if not ui:isOverBars(x, y) then
            local tile = game.camera:toTile(x, y)
            local ok, why = game.abilities:useLine(game.lineStart.x, game.lineStart.y, tile.x, tile.y)
            if not ok and why then ui:toast(why) end
        end
        game.lineStart = nil
        game.lineCost = nil
    end
end

function love.mousemoved(x, y, dx, dy)
    if state == 'playing' and game.dragging then
        game.camera:pan(-dx, -dy)
    end
end

function love.wheelmoved(_, y)
    if state ~= 'playing' or y == 0 then return end
    local mx, my = love.mouse.getPosition()
    game.camera:zoomAt(y > 0 and 1.15 or 1 / 1.15, mx, my)
end

function love.keypressed(key)
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
            title.difficultyIndex = (title.difficultyIndex - 2) % #DIFFICULTIES + 1
        elseif key == 'right' or key == 'd' then
            title.difficultyIndex = title.difficultyIndex % #DIFFICULTIES + 1
        elseif key == 's' then
            title.editingSeed = true
        elseif key == 'escape' and not isWeb() then
            love.event.quit()
        end
    elseif state == 'playing' then
        local n = tonumber(key)
        if n and ABILITY_ORDER[n] then
            game.abilities:select(ABILITY_ORDER[n])
            Audio.playSFX('click')
        elseif key == 'escape' then
            goToTitle()
        end
    elseif state == 'report' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            continueFromReport()
        end
    elseif state == 'gameover' then
        if key == 'return' or key == 'kpenter' or key == 'space' or key == 'escape' then
            goToTitle()
        end
    elseif state == 'annual' then
        if key == 'return' or key == 'kpenter' or key == 'space' then
            game.scoring:startEndless()
            state = 'playing'
            love.mouse.setVisible(false)
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
