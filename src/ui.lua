-- Screen space: bars, buttons, alerts, report card, title and end screens.
require('src.constants')
local Util = require('src.util')

local UI = {}
UI.__index = UI

TOP_BAR_H = 40
BOTTOM_BAR_H = 80
local FONT_PATH = 'assets/fonts/commodore64.ttf'
local ALERT_TTL = 7
local MAX_ALERTS = 4

local C = {
    bar = { 0.08, 0.09, 0.07, 0.92 },
    panel = { 0.1, 0.11, 0.09, 0.96 },
    text = { 0.93, 0.93, 0.85 },
    dim = { 0.6, 0.62, 0.5 },
    accent = { 0.58, 0.64, 0.36 },
    warn = { 0.92, 0.45, 0.35 },
    good = { 0.55, 0.82, 0.55 },
}

function UI.new()
    local self = setmetatable({}, UI)
    self.fonts = {
        small = love.graphics.newFont(FONT_PATH, 11),
        hud = love.graphics.newFont(FONT_PATH, 15),
        big = love.graphics.newFont(FONT_PATH, 26),
        title = love.graphics.newFont(FONT_PATH, 46),
    }
    self.icons = {
        select = love.graphics.newImage('assets/images/ui/plain_btn.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_icon.png'),
        storage = love.graphics.newImage('assets/images/ui/reload_button.png'),
        bridge = love.graphics.newImage('assets/images/ui/line_btn.png'),
        memo = love.graphics.newImage('assets/images/ui/seed_button.png'),
    }
    self.cursors = {
        select = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_cursor.png'),
        storage = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bridge = love.graphics.newImage('assets/images/ui/line_cursor.png'),
        memo = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
    }
    self.alerts = {}
    self.toastText, self.toastTtl = nil, 0
    self.buttons = {}
    local bw, bh, gap = 148, 60, 10
    local y = WINDOW_HEIGHT - BOTTOM_BAR_H + 10
    for i, tool in ipairs(ABILITY_ORDER) do
        self.buttons[#self.buttons + 1] = { tool = tool, x = 16 + (i - 1) * (bw + gap), y = y, w = bw, h = bh, key = tostring(i) }
    end
    return self
end

function UI:alert(text, tile)
    table.insert(self.alerts, 1, { text = text, ttl = ALERT_TTL, tile = tile })
    while #self.alerts > MAX_ALERTS do table.remove(self.alerts) end
end

function UI:toast(text)
    self.toastText, self.toastTtl = text, 2.2
end

function UI:clear()
    self.alerts = {}
    self.toastText = nil
end

function UI:update(dt)
    for i = #self.alerts, 1, -1 do
        self.alerts[i].ttl = self.alerts[i].ttl - dt
        if self.alerts[i].ttl <= 0 then table.remove(self.alerts, i) end
    end
    if self.toastTtl > 0 then
        self.toastTtl = self.toastTtl - dt
        if self.toastTtl <= 0 then self.toastText = nil end
    end
end

function UI:alertTiles()
    local tiles = {}
    for _, a in ipairs(self.alerts) do
        if a.tile then tiles[#tiles + 1] = a.tile end
    end
    return tiles
end

function UI:isOverBars(_, my)
    return my < TOP_BAR_H or my > WINDOW_HEIGHT - BOTTOM_BAR_H
end

function UI:buttonAt(mx, my)
    for _, b in ipairs(self.buttons) do
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            return b.tool
        end
    end
    return nil
end

local function setColor(c) love.graphics.setColor(c[1], c[2], c[3], c[4] or 1) end

function UI:centered(text, y, font, color)
    love.graphics.setFont(font)
    setColor(color or C.text)
    local w = font:getWidth(text)
    love.graphics.print(text, math.floor(WINDOW_WIDTH / 2 - w / 2), y)
end

-- HUD -------------------------------------------------------------------

function UI:drawTopBar(game)
    local s = game.scoring
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, 0, WINDOW_WIDTH, TOP_BAR_H)
    love.graphics.setFont(self.fonts.hud)
    local x = 16
    local function item(label, value, color)
        setColor(C.dim)
        love.graphics.print(label, x, 12)
        x = x + self.fonts.hud:getWidth(label) + 8
        setColor(color or C.text)
        love.graphics.print(value, x, 12)
        x = x + self.fonts.hud:getWidth(value) + 28
    end
    local qLabel = s.endless and ('Q' .. s.quarter) or ('Q' .. s.quarter .. '/' .. QUARTERS_PER_GAME)
    local timeColor = C.text
    if s.quarterTimer <= 15 and math.floor(s.quarterTimer * 2) % 2 == 0 then timeColor = C.warn end
    item(qLabel, Util.formatTime(s.quarterTimer), timeColor)
    item('STAFF', tostring(game.staffCount or 0))
    local fed = game.averageHunger and math.floor(game.averageHunger + 0.5) or 100
    item('FED', fed .. '%', fed < 35 and C.warn or C.text)
    item('OUTPUT', tostring(s.output))
    local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
    item('FOOD', stored .. '/' .. cap, cap == 0 and C.warn or C.text)
    item('LOGS', tostring(game.world.stock.logs), C.good)
    item('GOLD', tostring(game.world.stock.gold), C.good)
    item('COMPLAINTS', tostring(s.complaints), s.complaints > 0 and C.warn or C.text)
    local right = 'SEED ' .. tostring(game.seedString) .. '   M mute'
    setColor(C.dim)
    love.graphics.print(right, WINDOW_WIDTH - self.fonts.hud:getWidth(right) - 16, 12)
end

function UI:drawAlerts()
    love.graphics.setFont(self.fonts.small)
    local y = TOP_BAR_H + 8
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        local w = self.fonts.small:getWidth(a.text) + 12
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.rectangle('fill', 12, y, w, 18)
        love.graphics.setColor(C.warn[1], C.warn[2], C.warn[3], alpha)
        love.graphics.print(a.text, 18, y + 3)
        y = y + 22
    end
end

function UI:drawBottomBar(game)
    local abilities = game.abilities
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, WINDOW_HEIGHT - BOTTOM_BAR_H, WINDOW_WIDTH, BOTTOM_BAR_H)
    for _, b in ipairs(self.buttons) do
        local selected = abilities.selected == b.tool
        local affordable = abilities:canAfford(b.tool)
        if selected then
            love.graphics.setColor(0.28, 0.32, 0.2, 1)
        else
            love.graphics.setColor(0.16, 0.17, 0.14, 1)
        end
        love.graphics.rectangle('fill', b.x, b.y, b.w, b.h)
        if selected then
            setColor(C.accent)
            love.graphics.rectangle('line', b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1)
        end
        local icon = self.icons[b.tool]
        if affordable then love.graphics.setColor(1, 1, 1, 1) else love.graphics.setColor(0.4, 0.4, 0.4, 1) end
        love.graphics.draw(icon, b.x + 8, b.y + 6, 0, 3, 3)
        love.graphics.setFont(self.fonts.hud)
        setColor(affordable and C.text or C.dim)
        love.graphics.print(ABILITY_LABEL[b.tool], b.x + 62, b.y + 8)
        love.graphics.setFont(self.fonts.small)
        setColor(C.dim)
        love.graphics.print(abilities:costText(b.tool), b.x + 62, b.y + 30)
        love.graphics.print('[' .. b.key .. ']', b.x + 62, b.y + 44)
    end
    -- right side: selected worker or hints
    local px = WINDOW_WIDTH - 420
    local py = WINDOW_HEIGHT - BOTTOM_BAR_H + 8
    local w = game.selectedWorker
    if w and w.alive then
        love.graphics.setFont(self.fonts.hud)
        setColor(C.good)
        love.graphics.print(w.name, px, py)
        love.graphics.setFont(self.fonts.small)
        setColor(C.dim)
        love.graphics.print('the ' .. w.species .. ', ' .. w.roleInfo.label:lower(), px + self.fonts.hud:getWidth(w.name) + 12, py + 3)
        setColor(C.text)
        love.graphics.print(w:describeState(), px, py + 22)
        local work = w.slots[SLOT_WORK] and w.slots[SLOT_WORK].kind or 'empty'
        local pocket = w.slots[SLOT_PERSONAL] and w.slots[SLOT_PERSONAL].kind or 'empty'
        love.graphics.print('slot 1: ' .. work .. '   slot 2: ' .. pocket .. '   delivered ' .. w.delivered, px, py + 38)
        setColor(C.dim)
        love.graphics.print('HUNGER', px + 260, py + 22)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', px + 260, py + 38, 140, 10)
        local fill = 140 * (w.hunger / HUNGER_MAX)
        if w.hunger < HUNGER_EAT_THRESHOLD then setColor(C.warn) else setColor(C.good) end
        love.graphics.rectangle('fill', px + 260, py + 38, fill, 10)
    else
        love.graphics.setFont(self.fonts.small)
        setColor(C.dim)
        love.graphics.print('WASD or right-drag: pan   wheel: zoom   1-5: tools   MINE: drag over stone', px, py + 6)
        love.graphics.print('SELECT then click a morphi to see who is whining', px, py + 24)
        love.graphics.print('ESC: quit to title', px, py + 42)
    end
    if self.toastText then
        love.graphics.setFont(self.fonts.hud)
        local tw = self.fonts.hud:getWidth(self.toastText) + 20
        local tx = WINDOW_WIDTH / 2 - tw / 2
        local ty = WINDOW_HEIGHT - BOTTOM_BAR_H - 40
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', tx, ty, tw, 26)
        setColor(C.warn)
        love.graphics.print(self.toastText, tx + 10, ty + 5)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function UI:drawHUD(game)
    self:drawTopBar(game)
    self:drawAlerts()
    self:drawBottomBar(game)
end

function UI:drawCursor(tool, mx, my)
    local img = self.cursors[tool] or self.cursors.select
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, mx, my, 0, 2, 2)
end

-- Panels ----------------------------------------------------------------

function UI:panel(w, h)
    local x, y = WINDOW_WIDTH / 2 - w / 2, WINDOW_HEIGHT / 2 - h / 2
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle('fill', 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    setColor(C.panel)
    love.graphics.rectangle('fill', x, y, w, h)
    setColor(C.accent)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    return x, y
end

function UI:drawReport(report, scoring)
    local x, y = self:panel(640, 400)
    self:centered('QUARTERLY REPORT  Q' .. report.quarter, y + 24, self.fonts.big)
    love.graphics.setFont(self.fonts.hud)
    local rows = {
        { 'Output', report.output .. '  (food ' .. report.food .. ', logs ' .. report.logs .. ', gold ' .. report.gold .. ')' },
        { 'Fed', report.fedPct .. '%' },
        { 'Complaints', tostring(report.complaints) },
        { 'Attrition', tostring(report.attrition) },
        { 'Hires next quarter', '+' .. report.hires },
    }
    local ry = y + 90
    for _, row in ipairs(rows) do
        setColor(C.dim)
        love.graphics.print(row[1], x + 80, ry)
        setColor(C.text)
        love.graphics.print(row[2], x + 400, ry)
        ry = ry + 30
    end
    local gradeColor = C.good
    if report.grade == 'F' or report.grade == 'C' then gradeColor = C.warn end
    love.graphics.setFont(self.fonts.title)
    setColor(gradeColor)
    love.graphics.print(report.grade, x + 520, y + 110)
    local next_
    if scoring:yearComplete() then
        next_ = 'SPACE or click: annual review'
    else
        next_ = 'SPACE or click: next quarter'
    end
    self:centered(next_, y + 370, self.fonts.hud, C.dim)
end

function UI:drawTitle(title, highScore)
    love.graphics.setColor(0.09, 0.1, 0.08, 1)
    love.graphics.rectangle('fill', 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    self:centered('MORPHIS', 120, self.fonts.title)
    self:centered('Control the environment.', 190, self.fonts.hud, C.dim)
    self:centered('The morphis will manage themselves. Badly.', 212, self.fonts.hud, C.dim)
    local diff = DIFFICULTIES[title.difficultyIndex]
    self:centered('<  DIFFICULTY: ' .. diff.name .. '  >', 300, self.fonts.big)
    self:centered(diff.workers .. ' starting staff, hunger ' .. diff.drain .. '/s, score x' .. diff.multiplier, 340, self.fonts.small, C.dim)
    local seedText = 'SEED: ' .. title.seed
    if title.editingSeed then seedText = seedText .. (math.floor(love.timer.getTime() * 2) % 2 == 0 and '_' or ' ') end
    self:centered(seedText, 400, self.fonts.big, title.editingSeed and C.good or C.text)
    self:centered(title.editingSeed and 'type a seed, ENTER when done' or 'S to change the seed', 440, self.fonts.small, C.dim)
    self:centered('HIGH SCORE (' .. diff.name .. '): ' .. tostring(highScore), 500, self.fonts.hud)
    self:centered('ENTER or click to start', 570, self.fonts.big, C.good)
    self:centered('LEFT / RIGHT: difficulty     M: mute', 620, self.fonts.small, C.dim)
    self:centered('Pupper forages food, Twins chops logs, Cwab mines gold. Mark stone to mine and build storage from logs.', 660, self.fonts.small, C.dim)
    self:centered('You never control a morphi. That is the whole problem. Gold is worth 3, logs 2, food 1.', 680, self.fonts.small, C.dim)
end

function UI:drawGameOver(scoring, highScore, isNew)
    local x, y = self:panel(720, 360)
    self:centered('Human Resources has been notified.', y + 40, self.fonts.big, C.warn)
    self:centered('Everyone quit in Q' .. scoring.quarter, y + 100, self.fonts.hud, C.dim)
    self:centered('FINAL SCORE: ' .. scoring:finalScore(), y + 160, self.fonts.big)
    if isNew then
        self:centered('NEW HIGH SCORE', y + 210, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + 210, self.fonts.hud, C.dim)
    end
    self:centered('ENTER or click: back to the title', y + 300, self.fonts.hud, C.dim)
end

function UI:drawAnnual(scoring, highScore, isNew)
    local x, y = self:panel(720, 420)
    self:centered('ANNUAL REVIEW', y + 30, self.fonts.big, C.good)
    love.graphics.setFont(self.fonts.hud)
    local ry = y + 90
    for _, r in ipairs(scoring.reports) do
        setColor(C.dim)
        love.graphics.print('Q' .. r.quarter, x + 60, ry)
        setColor(C.text)
        love.graphics.print('output ' .. r.output .. '   complaints ' .. r.complaints .. '   quit ' .. r.attrition .. '   grade ' .. r.grade, x + 130, ry)
        ry = ry + 26
    end
    self:centered('FINAL SCORE: ' .. scoring:finalScore(), y + 240, self.fonts.big)
    if isNew then
        self:centered('NEW HIGH SCORE', y + 290, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + 290, self.fonts.hud, C.dim)
    end
    self:centered('ENTER or click: keep going (endless)     T: title', y + 360, self.fonts.hud, C.dim)
end

return UI
