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
        tiny = love.graphics.newFont(FONT_PATH, 9),
        small = love.graphics.newFont(FONT_PATH, 11),
        hud = love.graphics.newFont(FONT_PATH, 15),
        big = love.graphics.newFont(FONT_PATH, 26),
        title = love.graphics.newFont(FONT_PATH, 46),
    }
    self.foodIcon = love.graphics.newImage('assets/images/fruit/yp_apple.png')
    self.morphiIcon = love.graphics.newImage('assets/images/morphis/pupper-worker-walk.png')
    self.morphiQuad = love.graphics.newQuad(0, 0, 16, 16, self.morphiIcon:getWidth(), self.morphiIcon:getHeight())
    self.icons = {
        select = love.graphics.newImage('assets/images/ui/plain_btn.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_icon.png'),
        bridge = love.graphics.newImage('assets/images/ui/line_btn.png'),
        memo = love.graphics.newImage('assets/images/ui/seed_button.png'),
    }
    self.cursors = {
        select = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_cursor.png'),
        storage = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bin = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bed = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bridge = love.graphics.newImage('assets/images/ui/line_cursor.png'),
        memo = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
    }
    self.alerts = {}
    self.toastText, self.toastTtl = nil, 0
    self.unitButtons = {}
    self.buttons = {}
    local bw, bh, gap = 110, 60, 8
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

-- The C64 face is wide. Pick the largest of the given fonts that fits the
-- width, else wrap in the smallest. Returns the height used.
function UI:printFit(text, x, y, maxWidth, align, color, fonts)
    fonts = fonts or { self.fonts.hud, self.fonts.small, self.fonts.tiny }
    setColor(color or C.text)
    for _, font in ipairs(fonts) do
        if font:getWidth(text) <= maxWidth then
            love.graphics.setFont(font)
            local w = font:getWidth(text)
            local px = x
            if align == 'center' then px = x + (maxWidth - w) / 2 elseif align == 'right' then px = x + maxWidth - w end
            love.graphics.print(text, math.floor(px), y)
            return font:getHeight()
        end
    end
    local font = fonts[#fonts]
    love.graphics.setFont(font)
    local _, lines = font:getWrap(text, maxWidth)
    love.graphics.printf(text, x, y, maxWidth, align or 'left')
    return font:getHeight() * #lines
end

function UI:centeredFit(text, y, maxWidth, color, fonts)
    return self:printFit(text, (WINDOW_WIDTH - maxWidth) / 2, y, maxWidth, 'center', color, fonts)
end

-- Small resource icons for the bars. s is the pixel size of the icon.
function UI:iconLog(x, y, s)
    love.graphics.setColor(0.5, 0.35, 0.18)
    love.graphics.rectangle('fill', x, y + s * 0.3, s, s * 0.4)
    love.graphics.setColor(0.78, 0.6, 0.34)
    love.graphics.rectangle('fill', x + s * 0.78, y + s * 0.3, s * 0.22, s * 0.4)
    love.graphics.setColor(0.35, 0.24, 0.12)
    love.graphics.rectangle('fill', x + s * 0.86, y + s * 0.42, s * 0.08, s * 0.16)
end

function UI:iconGold(x, y, s)
    love.graphics.setColor(0.95, 0.8, 0.2)
    love.graphics.rectangle('fill', x + s * 0.15, y + s * 0.25, s * 0.7, s * 0.55)
    love.graphics.rectangle('fill', x + s * 0.3, y + s * 0.15, s * 0.4, s * 0.15)
    love.graphics.setColor(1, 0.96, 0.65)
    love.graphics.rectangle('fill', x + s * 0.25, y + s * 0.32, s * 0.18, s * 0.14)
    love.graphics.setColor(0.6, 0.45, 0.1)
    love.graphics.rectangle('fill', x + s * 0.5, y + s * 0.6, s * 0.28, s * 0.12)
end

function UI:iconFood(x, y, s)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.foodIcon, x, y, 0, s / 16, s / 16)
end

function UI:iconMorphi(x, y, s)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.morphiIcon, self.morphiQuad, x, y, 0, s / 16, s / 16)
end

function UI:iconComplaint(x, y, s)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle('fill', x + s * 0.1, y + s * 0.1, s * 0.8, s * 0.65)
    setColor(C.warn)
    love.graphics.rectangle('fill', x + s * 0.3, y + s * 0.2, s * 0.14, s * 0.35)
    love.graphics.rectangle('fill', x + s * 0.56, y + s * 0.2, s * 0.14, s * 0.35)
    love.graphics.rectangle('fill', x + s * 0.3, y + s * 0.6, s * 0.14, s * 0.1)
    love.graphics.rectangle('fill', x + s * 0.56, y + s * 0.6, s * 0.14, s * 0.1)
end

-- An open-topped bin drawn 2.5D: front face, right side, light rim, dark inside.
function UI:iconBin(x, y, s)
    love.graphics.setColor(0.55, 0.42, 0.24)
    love.graphics.rectangle('fill', x + s * 0.1, y + s * 0.4, s * 0.6, s * 0.5)
    love.graphics.setColor(0.38, 0.28, 0.15)
    love.graphics.polygon('fill', x + s * 0.7, y + s * 0.4, x + s * 0.9, y + s * 0.2, x + s * 0.9, y + s * 0.7, x + s * 0.7, y + s * 0.9)
    love.graphics.setColor(0.8, 0.64, 0.38)
    love.graphics.polygon('fill', x + s * 0.1, y + s * 0.4, x + s * 0.3, y + s * 0.2, x + s * 0.9, y + s * 0.2, x + s * 0.7, y + s * 0.4)
    love.graphics.setColor(0.2, 0.14, 0.08)
    love.graphics.polygon('fill', x + s * 0.2, y + s * 0.38, x + s * 0.34, y + s * 0.25, x + s * 0.82, y + s * 0.25, x + s * 0.66, y + s * 0.38)
    love.graphics.setColor(0.72, 0.56, 0.32)
    love.graphics.rectangle('fill', x + s * 0.14, y + s * 0.55, s * 0.52, s * 0.06)
    love.graphics.rectangle('fill', x + s * 0.14, y + s * 0.72, s * 0.52, s * 0.06)
end

-- A floor storage spot: a chalked square with a corner mark.
function UI:iconFloor(x, y, s)
    love.graphics.setColor(0.35, 0.3, 0.2)
    love.graphics.rectangle('fill', x + s * 0.12, y + s * 0.2, s * 0.76, s * 0.6)
    love.graphics.setColor(0.85, 0.8, 0.6)
    love.graphics.rectangle('line', x + s * 0.12 + 0.5, y + s * 0.2 + 0.5, s * 0.76 - 1, s * 0.6 - 1)
    love.graphics.line(x + s * 0.12, y + s * 0.2, x + s * 0.3, y + s * 0.2)
    love.graphics.line(x + s * 0.12, y + s * 0.2, x + s * 0.12, y + s * 0.38)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.foodIcon, x + s * 0.3, y + s * 0.3, 0, s * 0.4 / 16, s * 0.4 / 16)
end

function UI:iconBed(x, y, s)
    love.graphics.setColor(0.4, 0.28, 0.16)
    love.graphics.rectangle('fill', x + s * 0.1, y + s * 0.2, s * 0.8, s * 0.65)
    love.graphics.setColor(0.93, 0.9, 0.8)
    love.graphics.rectangle('fill', x + s * 0.16, y + s * 0.26, s * 0.68, s * 0.53)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle('fill', x + s * 0.2, y + s * 0.3, s * 0.2, s * 0.45)
    love.graphics.setColor(0.3, 0.45, 0.75)
    love.graphics.rectangle('fill', x + s * 0.44, y + s * 0.3, s * 0.4, s * 0.45)
end

function UI:iconForKind(kind, x, y, s)
    if kind == ITEM_FOOD or kind == CARGO_FOOD then self:iconFood(x, y, s)
    elseif kind == CARGO_LOGS then self:iconLog(x, y, s)
    elseif kind == CARGO_GOLD then self:iconGold(x, y, s)
    end
end

-- HUD -------------------------------------------------------------------

function UI:drawTopBar(game)
    local sc = game.scoring
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, 0, WINDOW_WIDTH, TOP_BAR_H)
    love.graphics.setFont(self.fonts.hud)
    local x = 16
    local ICON = 22
    local function text(value, color)
        love.graphics.setFont(self.fonts.hud)
        setColor(color or C.text)
        love.graphics.print(value, x, 12)
        x = x + self.fonts.hud:getWidth(value) + 26
    end
    local function icon(draw, value, color)
        draw(self, x, 9, ICON)
        x = x + ICON + 6
        love.graphics.setFont(self.fonts.hud)
        setColor(color or C.text)
        love.graphics.print(value, x, 12)
        x = x + self.fonts.hud:getWidth(value) + 26
    end
    local qLabel = sc.endless and ('Q' .. sc.quarter) or ('Q' .. math.min(sc.quarter, QUARTERS_PER_GAME) .. '/' .. QUARTERS_PER_GAME)
    local timeColor = C.text
    if sc.quarterTimer <= 15 and math.floor(sc.quarterTimer * 2) % 2 == 0 then timeColor = C.warn end
    setColor(C.dim)
    love.graphics.print(qLabel, x, 12)
    x = x + self.fonts.hud:getWidth(qLabel) + 8
    text(Util.formatTime(sc.quarterTimer), timeColor)
    icon(UI.iconMorphi, tostring(game.staffCount or 0))
    local fed = game.averageHunger and math.floor(game.averageHunger + 0.5) or 100
    setColor(C.dim)
    love.graphics.setFont(self.fonts.hud)
    love.graphics.print('FED', x, 12)
    x = x + self.fonts.hud:getWidth('FED') + 8
    text(fed .. '%', fed < 35 and C.warn or C.text)
    local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
    icon(UI.iconFood, stored .. '/' .. cap, cap == 0 and C.warn or C.text)
    icon(UI.iconLog, tostring(game.world.stock.logs), C.good)
    icon(UI.iconGold, tostring(game.world.stock.gold), C.good)
    icon(UI.iconComplaint, tostring(sc.complaints), sc.complaints > 0 and C.warn or C.text)
    setColor(C.dim)
    love.graphics.print('OUT', x, 12)
    x = x + self.fonts.hud:getWidth('OUT') + 8
    text(tostring(sc.output))
    -- right side: seed, follow, mute
    local right = 'seed ' .. tostring(game.seedString) .. '   M mute'
    if game.follow and game.selectedWorker then
        right = 'following ' .. game.selectedWorker.name .. ' (F)   ' .. right
    end
    self:printFit(right, x, 14, WINDOW_WIDTH - 16 - x, 'right', C.dim, { self.fonts.small, self.fonts.tiny })
end

function UI:drawAlerts()
    love.graphics.setFont(self.fonts.small)
    local y = TOP_BAR_H + 8
    local maxW = WINDOW_WIDTH - 40
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        local w = math.min(self.fonts.small:getWidth(a.text), maxW) + 12
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.rectangle('fill', 12, y, w, 18)
        love.graphics.setColor(C.warn[1], C.warn[2], C.warn[3], alpha)
        love.graphics.setFont(self.fonts.small)
        love.graphics.printf(a.text, 18, y + 3, maxW, 'left')
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
        local IS = 26
        if icon then
            if affordable then love.graphics.setColor(1, 1, 1, 1) else love.graphics.setColor(0.4, 0.4, 0.4, 1) end
            love.graphics.draw(icon, b.x + 5, b.y + 8, 0, IS / 16, IS / 16)
        elseif b.tool == ABILITY_STORAGE then
            self:iconFloor(b.x + 5, b.y + 8, IS)
        elseif b.tool == ABILITY_BIN then
            self:iconBin(b.x + 5, b.y + 8, IS)
        elseif b.tool == ABILITY_BED then
            self:iconBed(b.x + 5, b.y + 8, IS)
        end
        if not affordable and not icon then
            love.graphics.setColor(0.1, 0.1, 0.1, 0.55)
            love.graphics.rectangle('fill', b.x + 5, b.y + 8, IS, IS)
        end
        local lx = b.x + 5 + IS + 4
        self:printFit(ABILITY_LABEL[b.tool], lx, b.y + 8, b.x + b.w - lx - 4, 'left', affordable and C.text or C.dim, { self.fonts.hud, self.fonts.small, self.fonts.tiny })
        self:printFit(abilities:costText(b.tool), lx, b.y + 30, b.x + b.w - lx - 4, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        love.graphics.setFont(self.fonts.small)
        setColor(C.dim)
        love.graphics.print('[' .. b.key .. ']', lx, b.y + 44)
    end
    -- right side: selected worker or hints
    local px = WINDOW_WIDTH - 430
    local pw = 414
    local py = WINDOW_HEIGHT - BOTTOM_BAR_H + 8
    local w = game.selectedWorker
    if w and w.alive then
        love.graphics.setFont(self.fonts.hud)
        setColor(C.good)
        love.graphics.print(w.name, px, py)
        local nx = px + self.fonts.hud:getWidth(w.name) + 10
        self:printFit('the ' .. w.species .. ', ' .. w.roleInfo.label:lower(), nx, py + 3, px + pw - nx, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        self:printFit(w:describeState(), px, py + 22, pw - 150, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        -- inventory slots as boxes with icons
        local sx = px
        for i = 1, INVENTORY_SLOTS do
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle('fill', sx, py + 40, 24, 24)
            setColor(i == SLOT_WORK and C.accent or C.dim)
            love.graphics.rectangle('line', sx + 0.5, py + 40.5, 23, 23)
            local item = w.slots[i]
            if item then self:iconForKind(item.kind, sx + 3, py + 43, 18) end
            sx = sx + 30
        end
        love.graphics.setFont(self.fonts.tiny)
        setColor(C.dim)
        love.graphics.print('work  pocket', px, py + 65 - 2)
        self:printFit('delivered ' .. w.delivered .. '  complaints ' .. w.complaintCount, sx + 6, py + 46, pw - 150 - 66, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        -- hunger bar
        setColor(C.dim)
        love.graphics.setFont(self.fonts.tiny)
        love.graphics.print('HUNGER', px + pw - 140, py + 22)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', px + pw - 140, py + 36, 140, 10)
        local fill = 140 * (w.hunger / HUNGER_MAX)
        if w.hunger < HUNGER_EAT_THRESHOLD then setColor(C.warn) else setColor(C.good) end
        love.graphics.rectangle('fill', px + pw - 140, py + 36, fill, 10)
        setColor(C.dim)
        love.graphics.print('MORALE ' .. w:mood(), px + pw - 140, py + 50)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', px + pw - 140, py + 61, 140, 6)
        if w.morale < MORALE_LOW then setColor(C.warn) else setColor(C.accent) end
        love.graphics.rectangle('fill', px + pw - 140, py + 61, 140 * (w.morale / MORALE_MAX), 6)
        setColor(C.dim)
        love.graphics.print('F: follow  U: units', px + pw - 140, py + 70)
    else
        local lines = {
            'WASD / right-drag pan, wheel zoom, 1-7 tools, U units',
            'FLOOR spot: free, 1 item. BIN: 1 log, 4 items. BED: 2 logs.',
            'SELECT a morphi, then F to follow it. ESC asks.',
        }
        local ly = py + 4
        for _, line in ipairs(lines) do
            ly = ly + self:printFit(line, px, ly, pw, 'left', C.dim, { self.fonts.small, self.fonts.tiny }) + 4
        end
    end
    if self.toastText then
        love.graphics.setFont(self.fonts.hud)
        if self.fonts.hud:getWidth(self.toastText) > WINDOW_WIDTH - 80 then love.graphics.setFont(self.fonts.small) end
        local tw = love.graphics.getFont():getWidth(self.toastText) + 20
        local tx = WINDOW_WIDTH / 2 - tw / 2
        local ty = WINDOW_HEIGHT - BOTTOM_BAR_H - 40
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', tx, ty, tw, 26)
        setColor(C.warn)
        love.graphics.print(self.toastText, tx + 10, ty + 5)
        love.graphics.setFont(self.fonts.hud)
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

-- Units menu ------------------------------------------------------------

local UNIT_ROW_H = 54

-- Every living morphi at a glance: picture, name, species, role, task, hunger,
-- and a FOLLOW button. Button rects are kept in self.unitButtons for hit tests.
function UI:drawUnits(game, view)
    local units = {}
    for _, w in ipairs(game.workers) do
        if w.alive then units[#units + 1] = w end
    end
    local pw = 1000
    local ph = 74 + #units * UNIT_ROW_H + 30
    local x, y = self:panel(pw, ph)
    self.unitPanel = { x = x, y = y, w = pw, h = ph }
    self:centeredFit('UNITS  (' .. #units .. ' morphis)', y + 16, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    love.graphics.setFont(self.fonts.tiny)
    setColor(C.dim)
    love.graphics.print('MORPHI', x + 74, y + 56)
    love.graphics.print('TASK', x + 330, y + 56)
    love.graphics.print('HUNGER', x + 640, y + 56)
    love.graphics.print('MORALE', x + 770, y + 56)
    self.unitButtons = {}
    local ry = y + 70
    for _, w in ipairs(units) do
        local selected = game.selectedWorker == w
        if selected then
            love.graphics.setColor(0.2, 0.23, 0.15, 1)
            love.graphics.rectangle('fill', x + 12, ry, pw - 24, UNIT_ROW_H - 4)
        end
        -- picture
        local sheet = view and view.sheets[w.sheet]
        if sheet then
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle('fill', x + 18, ry + 2, 48, 46)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet.image, sheet.quads[1], x + 18, ry - 1, 0, 3, 3)
        end
        -- name, species, role
        love.graphics.setFont(self.fonts.hud)
        setColor(C.good)
        love.graphics.print(w.name, x + 74, ry + 4)
        self:printFit(w.species .. ', ' .. w.roleInfo.label:lower(), x + 74, ry + 26, 246, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        -- task
        self:printFit(w:describeState(), x + 330, ry + 8, 296, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        -- hunger
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x + 640, ry + 12, 120, 12)
        local frac = w.hunger / HUNGER_MAX
        if frac > 0.6 then setColor(C.good)
        elseif frac > HUNGER_EAT_THRESHOLD / HUNGER_MAX then love.graphics.setColor(0.95, 0.75, 0.3)
        else setColor(C.warn) end
        love.graphics.rectangle('fill', x + 640, ry + 12, 120 * frac, 12)
        self:printFit(math.floor(w.hunger + 0.5) .. '%', x + 640, ry + 28, 120, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        -- morale
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', x + 770, ry + 12, 80, 12)
        local mf = w.morale / MORALE_MAX
        if mf > 0.6 then setColor(C.good) elseif mf > MORALE_LOW / MORALE_MAX then love.graphics.setColor(0.95, 0.75, 0.3) else setColor(C.warn) end
        love.graphics.rectangle('fill', x + 770, ry + 12, 80 * mf, 12)
        self:printFit(w:mood(), x + 770, ry + 28, 80, 'left', mf > MORALE_LOW / MORALE_MAX and C.dim or C.warn, { self.fonts.small, self.fonts.tiny })
        -- follow button
        local following = game.follow and selected
        local bx, by, bw, bh = x + pw - 130, ry + 8, 112, 30
        if following then love.graphics.setColor(0.28, 0.32, 0.2, 1) else love.graphics.setColor(0.16, 0.17, 0.14, 1) end
        love.graphics.rectangle('fill', bx, by, bw, bh)
        setColor(following and C.accent or C.dim)
        love.graphics.rectangle('line', bx + 0.5, by + 0.5, bw - 1, bh - 1)
        self:printFit(following and 'FOLLOWING' or 'FOLLOW', bx, by + 8, bw, 'center', following and C.good or C.text, { self.fonts.small, self.fonts.tiny })
        self.unitButtons[#self.unitButtons + 1] = { worker = w, x = bx, y = by, w = bw, h = bh }
        ry = ry + UNIT_ROW_H
    end
    self:centeredFit('U or ESC: close     click FOLLOW to watch a morphi', y + ph - 24, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    love.graphics.setColor(1, 1, 1, 1)
end

function UI:unitButtonAt(mx, my)
    for _, b in ipairs(self.unitButtons) do
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then return b.worker end
    end
    return nil
end

function UI:insideUnitPanel(mx, my)
    local p = self.unitPanel
    return p and mx >= p.x and mx <= p.x + p.w and my >= p.y and my <= p.y + p.h
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
    local x, y = self:panel(700, 460)
    self:centeredFit('QUARTERLY REPORT  Q' .. report.quarter, y + 24, 660, C.text, { self.fonts.big, self.fonts.hud })
    love.graphics.setFont(self.fonts.hud)
    local rows = {
        { 'Output', tostring(report.output) },
        { 'Food stored', tostring(report.food), UI.iconFood },
        { 'Logs', tostring(report.logs), UI.iconLog },
        { 'Gold', tostring(report.gold), UI.iconGold },
        { 'Fed', report.fedPct .. '%' },
        { 'Complaints', tostring(report.complaints), UI.iconComplaint },
        { 'Attrition', tostring(report.attrition) },
        { 'Hires next quarter', '+' .. report.hires, UI.iconMorphi },
    }
    local ry = y + 80
    for _, row in ipairs(rows) do
        if row[3] then row[3](self, x + 60, ry - 3, 20) end
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print(row[1], x + 90, ry)
        setColor(C.text)
        love.graphics.print(row[2], x + 400, ry)
        ry = ry + 30
    end
    local gradeColor = C.good
    if report.grade == 'F' or report.grade == 'C' then gradeColor = C.warn end
    love.graphics.setFont(self.fonts.title)
    setColor(gradeColor)
    love.graphics.print(report.grade, x + 560, y + 120)
    local next_
    if scoring:yearComplete() then
        next_ = 'SPACE or click: annual review'
    else
        next_ = 'SPACE or click: next quarter'
    end
    self:centeredFit(next_, y + 420, 660, C.dim)
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
    self:centeredFit('Pupper forages food, Twins chops logs, Cwab mines gold. Mark stone to mine, bridge water, build bins and beds.', 660, WINDOW_WIDTH - 120, C.dim, { self.fonts.small, self.fonts.tiny })
    self:centeredFit('You never control a morphi. That is the whole problem. Gold is worth 3, logs 2, food 1.', 682, WINDOW_WIDTH - 120, C.dim, { self.fonts.small, self.fonts.tiny })
end

function UI:drawConfirmQuit()
    local x, y = self:panel(720, 230)
    self:centeredFit('Quit to the title screen?', y + 36, 680, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('This game will be lost.', y + 86, 680, C.dim)
    self:centeredFit('Y or ENTER: quit', y + 130, 680)
    self:centeredFit('any other key or click: keep playing', y + 160, 680, C.dim)
end

function UI:drawGameOver(scoring, highScore, isNew)
    local x, y = self:panel(720, 360)
    self:centeredFit('Human Resources has been notified.', y + 40, 680, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('Everyone quit in Q' .. scoring.quarter, y + 100, 680, C.dim)
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), y + 160, 680, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', y + 210, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + 210, self.fonts.hud, C.dim)
    end
    self:centeredFit('ENTER or click: back to the title', y + 300, 680, C.dim)
end

function UI:drawAnnual(scoring, highScore, isNew)
    local x, y = self:panel(720, 420)
    self:centered('ANNUAL REVIEW', y + 30, self.fonts.big, C.good)
    love.graphics.setFont(self.fonts.hud)
    local ry = y + 90
    for _, r in ipairs(scoring.reports) do
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print('Q' .. r.quarter, x + 60, ry)
        self:printFit('out ' .. r.output .. '  food ' .. r.food .. '  logs ' .. r.logs .. '  gold ' .. r.gold .. '  cmpl ' .. r.complaints .. '  quit ' .. r.attrition .. '  grade ' .. r.grade,
            x + 120, ry + 2, 560, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        ry = ry + 26
    end
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), y + 240, 680, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', y + 290, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + 290, self.fonts.hud, C.dim)
    end
    self:centeredFit('ENTER or click: keep going (endless)     T: title', y + 360, 680, C.dim)
end

return UI
