-- Screen space: bars, buttons, alerts, the season's tally, title and end screens.
require('src.constants')
local Util = require('src.util')
local Scoring = require('src.scoring')

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
    self.foodImages = {}
    for food, file in pairs(FOOD_SPRITE) do
        self.foodImages[food] = love.graphics.newImage('assets/images/fruit/' .. file)
    end
    self.morphiIcon = love.graphics.newImage('assets/images/morphis/pupper-worker-walk.png')
    self.morphiQuad = love.graphics.newQuad(0, 0, 16, 16, self.morphiIcon:getWidth(), self.morphiIcon:getHeight())
    self.icons = {
        select = love.graphics.newImage('assets/images/ui/plain_btn.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_icon.png'),
    }
    self.cursors = {
        select = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        mine = love.graphics.newImage('assets/images/ui/dig_cursor.png'),
        storage = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bin = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bed = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bridge = love.graphics.newImage('assets/images/ui/line_cursor.png'),
    }
    self.alerts = {}
    self.toastText, self.toastTtl = nil, 0
    self.unitButtons = {}
    self.buttons = {}
    self.topButtons = {}
    self.titleButtons = {}
    self.confirmButtons = {}
    self.touch = false -- true once a finger has touched the screen: no mouse cursor, bigger targets
    self:layout(love.graphics.getDimensions())
    return self
end

-- Layout ----------------------------------------------------------------
-- The HUD is drawn in a virtual space (vw x vh) scaled to the window, so a
-- phone gets readable text and big targets and a 4K screen is not a postage
-- stamp. Every hit test takes virtual coordinates: see toVirtual.

local function hit(r, x, y)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function UI:layout(w, h)
    self.winW, self.winH = w, h
    -- fit the 1280x800 design into the window on its tighter side, so a
    -- phone gets a small HUD with room for the map, and a big monitor a
    -- bigger one. Never below 0.55: text has to stay legible.
    self.scale = Util.clamp(math.min(w / 1280, h / 800), 0.55, 2.0)
    self.vw, self.vh = w / self.scale, h / self.scale
    self.narrow = self.vw < 980
    -- on a narrow screen the quick buttons get their own row under the stats
    TOP_BAR_H = self.narrow and 70 or 40
    -- tool buttons along the bottom
    local n = #ABILITY_ORDER
    local gap = 8
    self.panelW = self.narrow and 0 or Util.clamp(math.floor(self.vw * 0.33), 260, 414)
    local avail = self.vw - 32 - self.panelW - (self.panelW > 0 and 16 or 0) - (n - 1) * gap
    local bw = Util.clamp(math.floor(avail / n), 52, 110)
    self.compactButtons = bw < 96
    local y = self.vh - BOTTOM_BAR_H + 10
    self.buttons = {}
    for i, tool in ipairs(ABILITY_ORDER) do
        self.buttons[i] = { tool = tool, x = 16 + (i - 1) * (bw + gap), y = y, w = bw, h = 60, key = tostring(i) }
    end
    -- quick buttons at the right of the top bar, for fingers and for people who forget keys
    local defs = {
        { id = 'menu', label = 'MENU' }, { id = 'mute', label = 'MUTE' },
        { id = 'zoomin', label = '+' }, { id = 'zoomout', label = '-' },
        { id = 'follow', label = 'FOLLOW' }, { id = 'units', label = 'UNITS' }, { id = 'goal', label = 'GOAL' },
    }
    self.topButtons = {}
    local x = self.vw - 8
    local by = self.narrow and 38 or 6
    for _, d in ipairs(defs) do
        local bwid = self.fonts.small:getWidth(d.label) + 16
        x = x - bwid
        self.topButtons[#self.topButtons + 1] = { id = d.id, label = d.label, x = x, y = by, w = bwid, h = 28 }
        x = x - 6
    end
    self.topButtonsLeft = self.narrow and self.vw or x
end

function UI:toVirtual(x, y)
    return x / self.scale, y / self.scale
end

function UI:beginScaled()
    love.graphics.push()
    love.graphics.scale(self.scale)
end

function UI:endScaled()
    love.graphics.pop()
end

function UI:topButtonAt(mx, my)
    for _, b in ipairs(self.topButtons) do
        if hit(b, mx, my) then return b.id end
    end
    return nil
end

function UI:titleButtonAt(mx, my)
    for id, r in pairs(self.titleButtons) do
        if hit(r, mx, my) then return id end
    end
    return nil
end

function UI:confirmButtonAt(mx, my)
    for id, r in pairs(self.confirmButtons) do
        if hit(r, mx, my) then return id end
    end
    return nil
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
    return my < TOP_BAR_H or my > self.vh - BOTTOM_BAR_H
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
    love.graphics.print(text, math.floor(self.vw / 2 - w / 2), y)
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
    return self:printFit(text, (self.vw - maxWidth) / 2, y, maxWidth, 'center', color, fonts)
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

function UI:iconFoodKind(food, x, y, s)
    local img = self.foodImages[food]
    if not img then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, s / 16, s / 16)
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

-- A bin from above: wooden frame, dark open inside, lit from the top left.
function UI:iconBin(x, y, s)
    love.graphics.setColor(0.55, 0.42, 0.24)
    love.graphics.rectangle('fill', x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.84)
    love.graphics.setColor(0.16, 0.12, 0.06)
    love.graphics.rectangle('fill', x + s * 0.22, y + s * 0.22, s * 0.56, s * 0.56)
    love.graphics.setColor(0.8, 0.64, 0.38)
    love.graphics.rectangle('fill', x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.07)
    love.graphics.rectangle('fill', x + s * 0.08, y + s * 0.08, s * 0.07, s * 0.84)
    love.graphics.setColor(0.36, 0.26, 0.14)
    love.graphics.rectangle('fill', x + s * 0.08, y + s * 0.85, s * 0.84, s * 0.07)
    love.graphics.rectangle('fill', x + s * 0.85, y + s * 0.08, s * 0.07, s * 0.84)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.foodIcon, x + s * 0.26, y + s * 0.26, 0, s * 0.22 / 16, s * 0.22 / 16)
    love.graphics.draw(self.foodIcon, x + s * 0.52, y + s * 0.26, 0, s * 0.22 / 16, s * 0.22 / 16)
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

-- Planks laid across water, seen from above.
function UI:iconBridge(x, y, s)
    love.graphics.setColor(0.37, 0.56, 0.66)
    love.graphics.rectangle('fill', x + s * 0.05, y + s * 0.1, s * 0.9, s * 0.8)
    love.graphics.setColor(0.55, 0.7, 0.78)
    love.graphics.rectangle('fill', x + s * 0.1, y + s * 0.2, s * 0.25, s * 0.05)
    love.graphics.rectangle('fill', x + s * 0.6, y + s * 0.75, s * 0.25, s * 0.05)
    love.graphics.setColor(0.62, 0.47, 0.27)
    love.graphics.rectangle('fill', x + s * 0.05, y + s * 0.34, s * 0.9, s * 0.32)
    love.graphics.setColor(0.35, 0.26, 0.14)
    for i = 0, 4 do
        love.graphics.rectangle('fill', x + s * (0.08 + i * 0.19), y + s * 0.34, s * 0.03, s * 0.32)
    end
    love.graphics.rectangle('fill', x + s * 0.05, y + s * 0.3, s * 0.9, s * 0.05)
    love.graphics.rectangle('fill', x + s * 0.05, y + s * 0.65, s * 0.9, s * 0.05)
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

-- A small labelled button. Returns nothing; the rect is whatever was passed.
function UI:button(r, label, active, color)
    if active then love.graphics.setColor(0.28, 0.32, 0.2, 1) else love.graphics.setColor(0.16, 0.17, 0.14, 1) end
    love.graphics.rectangle('fill', r.x, r.y, r.w, r.h)
    setColor(active and C.accent or C.dim)
    love.graphics.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    self:printFit(label, r.x, r.y + math.floor((r.h - self.fonts.small:getHeight()) / 2), r.w, 'center', color or (active and C.good or C.text), { self.fonts.small, self.fonts.tiny })
end

function UI:drawTopBar(game)
    local sc = game.scoring
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, 0, self.vw, TOP_BAR_H)
    love.graphics.setFont(self.fonts.hud)
    local x = 16
    local ICON = 22
    local limit = self.topButtonsLeft - 10
    local function text(value, color)
        love.graphics.setFont(self.fonts.hud)
        setColor(color or C.text)
        love.graphics.print(value, x, 12)
        x = x + self.fonts.hud:getWidth(value) + (self.narrow and 14 or 26)
    end
    local function icon(draw, value, color)
        if x + ICON + 40 > limit then return end
        draw(self, x, 9, ICON)
        x = x + ICON + 6
        text(value, color)
    end
    local function label(word)
        if x + 60 > limit then return false end
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print(word, x, 12)
        x = x + self.fonts.hud:getWidth(word) + 8
        return true
    end
    local qLabel = sc:seasonLabel():upper()
    if game.mode == 'level' then qLabel = 'LEVEL ' .. game.level.index end
    local timeColor = C.text
    if sc.quarterTimer <= 15 and math.floor(sc.quarterTimer * 2) % 2 == 0 then timeColor = C.warn end
    label(self.narrow and qLabel:gsub('LEVEL ', 'L'):sub(1, 3) or qLabel)
    text(Util.formatTime(sc.quarterTimer), timeColor)
    if game.mode == 'level' and label('PTS') then
        local spent, par = game.world.spent, game.level.def.par
        text(spent .. '/' .. par, spent > par and C.warn or C.good)
    end
    icon(UI.iconMorphi, tostring(game.staffCount or 0))
    local fed = game.averageHunger and math.floor(game.averageHunger + 0.5) or 100
    if label('FED') then text(fed .. '%', fed < 35 and C.warn or C.text) end
    local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
    icon(UI.iconFood, stored .. '/' .. cap, cap == 0 and C.warn or C.text)
    icon(UI.iconLog, tostring(game.world.stock.logs), C.good)
    icon(UI.iconGold, tostring(game.world.stock.gold), C.good)
    icon(UI.iconComplaint, tostring(sc.complaints), sc.complaints > 0 and C.warn or C.text)
    if game.mode ~= 'level' and not self.narrow and label('HAUL') then text(tostring(sc.output)) end
    -- following / seed, in whatever room is left before the buttons
    local right = ''
    if game.follow and game.selectedWorker then right = 'following ' .. game.selectedWorker.name end
    if limit - x > 220 and not self.narrow and game.mode ~= 'level' then right = right .. (right ~= '' and '   ' or '') .. 'seed ' .. tostring(game.seedString) end
    if right ~= '' and limit - x > 60 then
        self:printFit(right, x, 14, limit - x, 'right', C.dim, { self.fonts.small, self.fonts.tiny })
    end
    for _, b in ipairs(self.topButtons) do
        local active = (b.id == 'follow' and game.follow) or (b.id == 'mute' and game.muted)
        self:button(b, b.label, active)
    end
end

function UI:drawAlerts()
    love.graphics.setFont(self.fonts.small)
    local y = TOP_BAR_H + 8
    local maxW = self.vw - 40
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        local _, lines = self.fonts.small:getWrap(a.text, maxW)
        local h = #lines * self.fonts.small:getHeight() + 6
        local w = math.min(self.fonts.small:getWidth(a.text), maxW) + 12
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.rectangle('fill', 12, y, w, h)
        love.graphics.setColor(C.warn[1], C.warn[2], C.warn[3], alpha)
        love.graphics.setFont(self.fonts.small)
        love.graphics.printf(a.text, 18, y + 3, maxW, 'left')
        y = y + h + 4
    end
end

-- Cost text on one line: drop the detail after the comma when it will not fit.
function UI:fitLine(text, width)
    if self.fonts.tiny:getWidth(text) > width then text = text:gsub(',.*', '') end
    if self.fonts.tiny:getWidth(text) > width then text = text:gsub(' logs?', '') end
    return text
end

function UI:drawToolIcon(tool, x, y, size, affordable)
    local icon = self.icons[tool]
    if icon then
        if affordable then love.graphics.setColor(1, 1, 1, 1) else love.graphics.setColor(0.4, 0.4, 0.4, 1) end
        love.graphics.draw(icon, x, y, 0, size / 16, size / 16)
        return
    end
    if tool == ABILITY_STORAGE then self:iconFloor(x, y, size)
    elseif tool == ABILITY_BIN then self:iconBin(x, y, size)
    elseif tool == ABILITY_BED then self:iconBed(x, y, size)
    elseif tool == ABILITY_BRIDGE then self:iconBridge(x, y, size)
    end
    if not affordable then
        love.graphics.setColor(0.1, 0.1, 0.1, 0.55)
        love.graphics.rectangle('fill', x, y, size, size)
    end
end

function UI:drawBottomBar(game)
    local abilities = game.abilities
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, self.vh - BOTTOM_BAR_H, self.vw, BOTTOM_BAR_H)
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
        if self.compactButtons then
            -- icon on top, label under it, cost only when affordable is in doubt
            local IS = 24
            self:drawToolIcon(b.tool, b.x + math.floor((b.w - IS) / 2), b.y + 5, IS, affordable)
            self:printFit(ABILITY_LABEL[b.tool], b.x, b.y + 32, b.w, 'center', affordable and C.text or C.dim, { self.fonts.tiny })
            self:printFit((abilities:costText(b.tool):gsub(',.*', '')), b.x, b.y + 44, b.w, 'center', C.dim, { self.fonts.tiny })
        else
            local IS = 26
            self:drawToolIcon(b.tool, b.x + 5, b.y + 8, IS, affordable)
            local lx = b.x + 5 + IS + 4
            self:printFit(ABILITY_LABEL[b.tool], lx, b.y + 8, b.x + b.w - lx - 4, 'left', affordable and C.text or C.dim, { self.fonts.hud, self.fonts.small, self.fonts.tiny })
            self:printFit(self:fitLine(abilities:costText(b.tool), b.x + b.w - lx - 4), lx, b.y + 30, b.x + b.w - lx - 4, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            love.graphics.setFont(self.fonts.small)
            setColor(C.dim)
            love.graphics.print('[' .. b.key .. ']', lx, b.y + 44)
        end
    end
    -- right side: selected worker or hints
    local w = game.selectedWorker
    if self.panelW > 0 then
        local pw = self.panelW
        local px = self.vw - pw - 16
        local py = self.vh - BOTTOM_BAR_H + 8
        if w and w.alive then
            love.graphics.setFont(self.fonts.hud)
            setColor(C.good)
            love.graphics.print(w.name, px, py)
            local nx = px + self.fonts.hud:getWidth(w.name) + 10
            self:printFit('the ' .. w.species .. ', ' .. w.roleInfo.label:lower() .. ', eats', nx, py + 3, px + pw - nx - 24, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            self:iconFoodKind(w.diet, px + pw - 160, py - 2, 18)
            self:printFit(w:describeState(), px, py + 22, pw - 150, 'left', C.text, { self.fonts.small, self.fonts.tiny })
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
            self:printFit('hauled ' .. w.delivered .. '  hardships ' .. w.complaintCount, sx + 6, py + 46, pw - 150 - 66, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            local bx = px + pw - 140
            setColor(C.dim)
            love.graphics.setFont(self.fonts.tiny)
            love.graphics.print('HUNGER', bx, py + 22)
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle('fill', bx, py + 36, 140, 10)
            if w.hunger < HUNGER_EAT_THRESHOLD then setColor(C.warn) else setColor(C.good) end
            love.graphics.rectangle('fill', bx, py + 36, 140 * (w.hunger / HUNGER_MAX), 10)
            setColor(C.dim)
            love.graphics.print('MORALE ' .. w:mood(), bx, py + 50)
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle('fill', bx, py + 61, 140, 6)
            if w.morale < MORALE_LOW then setColor(C.warn) else setColor(C.accent) end
            love.graphics.rectangle('fill', bx, py + 61, 140 * (w.morale / MORALE_MAX), 6)
            setColor(C.dim)
            love.graphics.print(self.touch and 'FOLLOW and UNITS are up top' or 'F: follow  U: units', bx, py + 70)
        else
            local lines
            if self.touch then
                lines = {
                    'SELECT: drag pans, tap picks a morphi.',
                    'Pinch to zoom. FOLLOW and UNITS up top.',
                    'FLOOR free, BIN 1 log, BED 2 logs.',
                }
            else
                lines = {
                    'WASD / drag pan, wheel zoom, 1-6 tools, U units',
                    'FLOOR spot: free, 1 item. BIN: 1 log, 4 items. BED: 2 logs.',
                    'SELECT a morphi, then F to follow it. ESC asks.',
                }
            end
            local ly = py + 4
            for _, line in ipairs(lines) do
                ly = ly + self:printFit(line, px, ly, pw, 'left', C.dim, { self.fonts.small, self.fonts.tiny }) + 4
            end
        end
    elseif w and w.alive then
        -- narrow: one line above the bar
        local line = w.name .. ': ' .. w:describeState() .. '  hunger ' .. math.floor(w.hunger + 0.5) .. '%  ' .. w:mood()
        local ty = self.vh - BOTTOM_BAR_H - 22
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', 8, ty, self.vw - 16, 20)
        self:printFit(line, 14, ty + 4, self.vw - 28, 'left', C.text, { self.fonts.small, self.fonts.tiny })
    end
    if self.toastText then
        love.graphics.setFont(self.fonts.hud)
        if self.fonts.hud:getWidth(self.toastText) > self.vw - 80 then love.graphics.setFont(self.fonts.small) end
        local tw = math.min(love.graphics.getFont():getWidth(self.toastText) + 20, self.vw - 16)
        local tx = self.vw / 2 - tw / 2
        local ty = self.vh - BOTTOM_BAR_H - (self.panelW > 0 and 40 or 52)
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

-- Drawn in window space, not the scaled HUD space.
function UI:drawCursor(tool, mx, my)
    if self.touch then return end
    local img = self.cursors[tool] or self.cursors.select
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, mx, my, 0, 2 * self.scale, 2 * self.scale)
end

-- Units menu ------------------------------------------------------------

-- Every living morphi at a glance: picture, name, species, role, task, hunger,
-- morale and a FOLLOW button. Rows shrink to fit the screen.
function UI:drawUnits(game, view)
    local units = {}
    for _, w in ipairs(game.workers) do
        if w.alive then units[#units + 1] = w end
    end
    local pw = math.min(1000, self.vw - 24)
    local rowH = Util.clamp(math.floor((self.vh - 120) / math.max(#units, 1)), 30, 54)
    local ph = 74 + #units * rowH + 30
    local x, y = self:panel(pw, ph)
    self.unitPanel = { x = x, y = y, w = pw, h = ph }
    self:centeredFit('UNITS  (' .. #units .. ' morphis)', y + 16, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    local cName, cTask, cHunger, cMorale = x + 18 + rowH, x + math.floor(pw * 0.34), x + math.floor(pw * 0.62), x + math.floor(pw * 0.76)
    local wide = pw >= 760
    love.graphics.setFont(self.fonts.tiny)
    setColor(C.dim)
    love.graphics.print('MORPHI', cName, y + 56)
    love.graphics.print('TASK', cTask, y + 56)
    love.graphics.print('HUNGER', cHunger, y + 56)
    if wide then love.graphics.print('MORALE', cMorale, y + 56) end
    self.unitButtons = {}
    local ry = y + 70
    local spriteScale = (rowH - 6) / 16
    for _, w in ipairs(units) do
        local selected = game.selectedWorker == w
        if selected then
            love.graphics.setColor(0.2, 0.23, 0.15, 1)
            love.graphics.rectangle('fill', x + 12, ry, pw - 24, rowH - 4)
        end
        local sheet = view and view.sheets[w.sheet]
        if sheet then
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle('fill', x + 18, ry + 2, rowH - 6, rowH - 6)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet.image, sheet.quads[1], x + 18, ry - 1, 0, spriteScale, spriteScale)
        end
        local nameFont = rowH >= 44 and self.fonts.hud or self.fonts.small
        love.graphics.setFont(nameFont)
        setColor(C.good)
        love.graphics.print(w.name, cName, ry + 4)
        self:iconFoodKind(w.diet, cName + nameFont:getWidth(w.name) + 6, ry + 2, 16)
        if rowH >= 44 then
            self:printFit(w.species .. ', ' .. w.roleInfo.label:lower(), cName, ry + 26, cTask - cName - 8, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        else
            local nw = nameFont:getWidth(w.name) + 8
            self:printFit(w.roleInfo.label:lower(), cName + nw, ry + 6, cTask - cName - nw - 8, 'left', C.dim, { self.fonts.tiny })
        end
        self:printFit(w:describeState(), cTask, ry + 8, cHunger - cTask - 10, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        local barW = (wide and cMorale or (x + pw - 140)) - cHunger - 12
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', cHunger, ry + 10, barW, 10)
        local frac = w.hunger / HUNGER_MAX
        if frac > 0.6 then setColor(C.good)
        elseif frac > HUNGER_EAT_THRESHOLD / HUNGER_MAX then love.graphics.setColor(0.95, 0.75, 0.3)
        else setColor(C.warn) end
        love.graphics.rectangle('fill', cHunger, ry + 10, barW * frac, 10)
        if rowH >= 40 then
            self:printFit(math.floor(w.hunger + 0.5) .. '%', cHunger, ry + 24, barW, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        end
        if wide then
            local mw = (x + pw - 140) - cMorale - 12
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle('fill', cMorale, ry + 10, mw, 10)
            local mf = w.morale / MORALE_MAX
            if mf > 0.6 then setColor(C.good) elseif mf > MORALE_LOW / MORALE_MAX then love.graphics.setColor(0.95, 0.75, 0.3) else setColor(C.warn) end
            love.graphics.rectangle('fill', cMorale, ry + 10, mw * mf, 10)
            if rowH >= 40 then
                self:printFit(w:mood(), cMorale, ry + 24, mw, 'left', mf > MORALE_LOW / MORALE_MAX and C.dim or C.warn, { self.fonts.small, self.fonts.tiny })
            end
        end
        local following = game.follow and selected
        local r = { x = x + pw - 130, y = ry + math.floor((rowH - 4 - 28) / 2), w = 112, h = 28 }
        self:button(r, following and 'FOLLOWING' or 'FOLLOW', following)
        self.unitButtons[#self.unitButtons + 1] = { worker = w, x = r.x, y = r.y, w = r.w, h = r.h }
        ry = ry + rowH
    end
    self:centeredFit(self.touch and 'tap outside to close     tap FOLLOW to watch a morphi' or 'U or ESC: close     click FOLLOW to watch a morphi', y + ph - 24, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    love.graphics.setColor(1, 1, 1, 1)
end

function UI:unitButtonAt(mx, my)
    for _, b in ipairs(self.unitButtons) do
        if hit(b, mx, my) then return b.worker end
    end
    return nil
end

function UI:insideUnitPanel(mx, my)
    return hit(self.unitPanel, mx, my)
end

-- Panels ----------------------------------------------------------------

-- A centred panel no bigger than the screen. Returns x, y, w, h.
function UI:panel(w, h)
    w = math.min(w, self.vw - 16)
    h = math.min(h, self.vh - 16)
    local x, y = math.floor(self.vw / 2 - w / 2), math.floor(self.vh / 2 - h / 2)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle('fill', 0, 0, self.vw, self.vh)
    setColor(C.panel)
    love.graphics.rectangle('fill', x, y, w, h)
    setColor(C.accent)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    return x, y, w, h
end

function UI:drawReport(report, scoring)
    local x, y, pw, ph = self:panel(700, 460)
    self:centeredFit('END OF ' .. Scoring.seasonName(report.quarter):upper(), y + 20, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    love.graphics.setFont(self.fonts.hud)
    local rows = {
        { 'Hauled in', tostring(report.output) },
        { 'Food stored', tostring(report.food), UI.iconFood },
        { 'Logs', tostring(report.logs), UI.iconLog },
        { 'Gold', tostring(report.gold), UI.iconGold },
        { 'Fed', report.fedPct .. '%' },
        { 'Hardships', tostring(report.complaints), UI.iconComplaint },
        { 'Lost to the wilds', tostring(report.attrition) },
        { 'Migrants arriving', '+' .. report.hires, UI.iconMorphi },
    }
    local rs = math.min(30, math.floor((ph - 130) / #rows))
    local ry = y + 70
    local lx, vx = x + math.floor(pw * 0.1), x + math.floor(pw * 0.55)
    for _, row in ipairs(rows) do
        if row[3] then row[3](self, lx, ry - 3, 20) end
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print(row[1], lx + 30, ry)
        setColor(C.text)
        love.graphics.print(row[2], vx, ry)
        ry = ry + rs
    end
    local gradeColor = C.good
    if report.grade == 'F' or report.grade == 'C' then gradeColor = C.warn end
    love.graphics.setFont(self.fonts.title)
    setColor(gradeColor)
    love.graphics.print(report.grade, x + pw - 110, y + 70 + rs)
    local next_
    if scoring:yearComplete() then
        next_ = (self.touch and 'tap' or 'SPACE or click') .. ': the year ends'
    else
        next_ = (self.touch and 'tap' or 'SPACE or click') .. ': next season'
    end
    self:centeredFit(next_, y + ph - 36, pw - 40, C.dim)
end

function UI:drawTitle(title, highScore)
    love.graphics.setColor(0.09, 0.1, 0.08, 1)
    love.graphics.rectangle('fill', 0, 0, self.vw, self.vh)
    self.titleButtons = {}
    local cx = self.vw / 2
    local g = self.vh / 800            -- gaps shrink on short screens, fonts do not
    local function gap(px) return math.floor(px * g) end
    local y = gap(40)
    self:centered('MORPHIS', y, self.fonts.title)
    y = y + 46 + gap(14)
    self:centered('A small band settling the harsh wilds.', y, self.fonts.hud, C.dim)
    y = y + 17
    self:centered('They will look after themselves. Badly.', y, self.fonts.hud, C.dim)
    y = y + 15 + gap(36)
    -- what to play: a level, or the open wilds
    local opt = title.options[title.option]
    local row1
    if opt.kind == 'level' then
        row1 = 'LEVEL ' .. opt.index .. ': ' .. (opt.locked and 'LOCKED' or opt.def.name:upper())
    else
        row1 = 'FREE PLAY'
    end
    local nw = self.fonts.big:getWidth(row1)
    self:centered(row1, y, self.fonts.big, opt.locked and C.dim or C.text)
    local aw, ah = 44, 40
    self.titleButtons.left = { x = cx - nw / 2 - 20 - aw, y = y - 7, w = aw, h = ah }
    self.titleButtons.right = { x = cx + nw / 2 + 20, y = y - 7, w = aw, h = ah }
    self:button(self.titleButtons.left, '<', false)
    self:button(self.titleButtons.right, '>', false)
    y = y + 26 + 8
    local diff = DIFFICULTIES[title.difficultyIndex]
    if opt.kind == 'level' then
        if opt.locked then
            self:centered('clear level ' .. (opt.index - 1) .. ' first', y, self.fonts.small, C.dim)
        else
            self:centeredFit(opt.def.blurb, y, self.vw - 80, C.dim, { self.fonts.small, self.fonts.tiny })
            y = y + 14
            local best = opt.best and ('   best ' .. opt.best .. (opt.best <= opt.def.par and ' (3 stars)' or '')) or ''
            self:centered(opt.def.points .. ' points to spend, par ' .. opt.def.par .. best, y, self.fonts.small, C.text)
        end
        y = y + 11 + gap(30)
    else
        local dname = diff.name:upper()
        local dw = self.fonts.hud:getWidth(dname)
        self:centered(dname, y, self.fonts.hud)
        self.titleButtons.diffLeft = { x = cx - dw / 2 - 16 - 36, y = y - 8, w = 36, h = 30 }
        self.titleButtons.diffRight = { x = cx + dw / 2 + 16, y = y - 8, w = 36, h = 30 }
        self:button(self.titleButtons.diffLeft, '<', false)
        self:button(self.titleButtons.diffRight, '>', false)
        y = y + 18
        self:centered(diff.workers .. ' settlers, hunger ' .. diff.drain .. '/s, score x' .. diff.multiplier .. ', seasons and migrants', y, self.fonts.small, C.dim)
        y = y + 11 + gap(30)
        local seedText = 'SEED: ' .. title.seed
        if title.editingSeed then seedText = seedText .. (math.floor(love.timer.getTime() * 2) % 2 == 0 and '_' or ' ') end
        self:centered(seedText, y, self.fonts.big, title.editingSeed and C.good or C.text)
        local sw = self.fonts.big:getWidth(seedText) + 40
        self.titleButtons.seed = { x = cx - sw / 2, y = y - 8, w = sw, h = 42 }
        y = y + 26 + 8
        self:centered(title.editingSeed and 'type a seed, ENTER when done' or (self.touch and 'tap the seed to change it' or 'S to change the seed'), y, self.fonts.small, C.dim)
    end
    y = y + 11 + gap(24)
    if opt.kind == 'free' then
        self:centered('HIGH SCORE (' .. diff.name .. '): ' .. tostring(highScore), y, self.fonts.hud)
    end
    y = y + 15 + gap(30)
    local startText = self.touch and 'TAP TO START' or 'ENTER or click to start'
    local stw = self.fonts.big:getWidth(startText) + 60
    self.titleButtons.start = { x = cx - stw / 2, y = y, w = stw, h = 54 }
    setColor(C.accent)
    love.graphics.rectangle('line', self.titleButtons.start.x + 0.5, y + 0.5, stw - 1, 53)
    self:centered(startText, y + 14, self.fonts.big, C.good)
    y = y + 54 + gap(14)
    if not self.touch then
        self:centered('LEFT / RIGHT: level     UP / DOWN: difficulty     M: mute     F11: fullscreen', y, self.fonts.small, C.dim)
        y = y + 11 + gap(14)
    end
    y = y + self:centeredFit('Every morphi eats one food and nothing else. Bridges and bins cost points, mining is free, logs are points.', y, self.vw - 60, C.dim, { self.fonts.small, self.fonts.tiny }) + 4
    self:centeredFit('You never control a morphi. Keep them all fed to the end of the level, and spend as little as you can.', y, self.vw - 60, C.dim, { self.fonts.small, self.fonts.tiny })
    self.titleButtons.mute = { x = self.vw - 90, y = 10, w = 80, h = 28 }
    self:button(self.titleButtons.mute, title.muted and 'UNMUTE' or 'MUTE', title.muted)
end

local function starText(n)
    local t = ''
    for i = 1, 3 do t = t .. (i <= n and '*' or '-') .. (i < 3 and ' ' or '') end
    return t
end

function UI:drawLevelClear(game)
    local lv = game.level
    local x, y, pw, ph = self:panel(720, 360)
    self:centeredFit('LEVEL ' .. lv.index .. ' CLEAR: ' .. lv.def.name:upper(), y + 28, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    self:centered(starText(lv.stars), y + 78, self.fonts.title, lv.stars == 3 and C.good or C.text)
    local spent, par = game.world.spent, lv.def.par
    self:centeredFit('spent ' .. spent .. ' point' .. (spent == 1 and '' or 's') .. ', par ' .. par, y + 150, pw - 40, C.text, { self.fonts.hud })
    if spent > par then
        self:centeredFit('a sharper eye spends ' .. par .. '. Look for the narrow crossing, the thin wall, the grove.', y + 180, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    else
        self:centeredFit('That is as cheap as it gets.', y + 180, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    end
    if lv.isNewBest then self:centered('NEW BEST', y + 215, self.fonts.hud, C.good) end
    local go = self.touch and 'tap' or 'ENTER or click'
    if lv.index < #game.levels then
        self:centeredFit(go .. ': level ' .. (lv.index + 1) .. '     ' .. (self.touch and 'MENU: title' or 'ESC: title'), y + ph - 40, pw - 40, C.dim)
    else
        self:centeredFit('All five levels clear. ' .. go .. ': back to the title', y + ph - 40, pw - 40, C.dim)
    end
end

-- What this level asks for. Opens paused at the start and from GOAL up top.
function UI:drawGoal(game)
    local x, y, pw, ph = self:panel(760, 310)
    local lines = {}
    if game.mode == 'level' then
        local def = game.level.def
        self:centeredFit('LEVEL ' .. game.level.index .. ': ' .. def.name:upper(), y + 22, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
        lines = {
            { def.intro, C.text },
            { 'Keep everyone fed until the clock runs out. Nobody may be lost.', C.text },
            { def.points .. ' points to spend, par ' .. def.par .. '. Bridges, bins and beds cost points. Mining is free. Logs are points.', C.dim },
        }
    else
        self:centeredFit('FREE PLAY', y + 22, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
        lines = {
            { 'A random map, four seasons, migrants when the haul is good.', C.text },
            { 'Keep the band fed. Hardships and hunger wear morale down; at zero a morphi leaves.', C.text },
            { 'Mark FLOOR spots or BINS so foragers can store food, MINE stone, BRIDGE the rivers.', C.dim },
        }
    end
    local ly = y + 64
    for _, line in ipairs(lines) do
        ly = ly + self:printFit(line[1], x + 24, ly, pw - 48, 'left', line[2], { self.fonts.hud, self.fonts.small, self.fonts.tiny }) + 10
    end
    -- who eats what
    ly = ly + 6
    love.graphics.setFont(self.fonts.small)
    setColor(C.dim)
    love.graphics.print('WHO EATS WHAT', x + 24, ly)
    ly = ly + 18
    local seen = {}
    local cx = x + 24
    for _, w in ipairs(game.workers) do
        if w.alive and not seen[w.sheet] then
            seen[w.sheet] = true
            local label = w.species .. ' eats ' .. w.diet
            local lw = self.fonts.small:getWidth(label) + 26
            if cx + lw > x + pw - 24 then cx = x + 24; ly = ly + 24 end
            self:iconFoodKind(w.diet, cx, ly - 3, 18)
            love.graphics.setFont(self.fonts.small)
            setColor(C.text)
            love.graphics.print(label, cx + 22, ly)
            cx = cx + lw + 16
        end
    end
    local go = self.touch and 'tap' or 'ENTER, G or click'
    self:centeredFit(go .. ': ' .. (game.started and 'back to it' or 'begin') .. '     GOAL up top brings this back', y + ph - 36, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
end

function UI:drawLevelFailed(game)
    local lv = game.level
    local x, y, pw, ph = self:panel(720, 260)
    self:centeredFit('LEVEL ' .. lv.index .. ' FAILED', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit(game.failReason or 'Somebody left the band.', y + 86, pw - 40, C.text, { self.fonts.hud, self.fonts.small })
    self:centeredFit('Nobody can be lost. Feed everyone to the end of the clock.', y + 120, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    local go = self.touch and 'tap' or 'ENTER or click'
    self:centeredFit(go .. ': try again     ' .. (self.touch and 'MENU: title' or 'ESC: title'), y + ph - 40, pw - 40, C.dim)
end

function UI:drawConfirmQuit()
    local x, y, pw, ph = self:panel(720, 230)
    self:centeredFit('Quit to the title screen?', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('This game will be lost.', y + 76, pw - 40, C.dim)
    local bw, bh = 180, 44
    self.confirmButtons.yes = { x = x + pw / 2 - bw - 12, y = y + ph - 80, w = bw, h = bh }
    self.confirmButtons.no = { x = x + pw / 2 + 12, y = y + ph - 80, w = bw, h = bh }
    self:button(self.confirmButtons.yes, self.touch and 'QUIT' or 'QUIT (Y)', false, C.warn)
    self:button(self.confirmButtons.no, self.touch and 'KEEP PLAYING' or 'KEEP PLAYING (ESC)', true)
end

function UI:drawGameOver(scoring, highScore, isNew)
    local x, y, pw, ph = self:panel(720, 360)
    self:centeredFit('The wilds took them all.', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('Nobody was left by ' .. Scoring.seasonName(scoring.quarter):lower(), y + 80, pw - 40, C.dim)
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), y + math.floor(ph * 0.42), pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', y + math.floor(ph * 0.58), self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + math.floor(ph * 0.58), self.fonts.hud, C.dim)
    end
    self:centeredFit((self.touch and 'tap' or 'ENTER or click') .. ': back to the title', y + ph - 40, pw - 40, C.dim)
end

function UI:drawAnnual(scoring, highScore, isNew)
    local x, y, pw, ph = self:panel(720, 420)
    self:centered('THE YEAR IS OVER', y + 24, self.fonts.big, C.good)
    love.graphics.setFont(self.fonts.hud)
    local rs = math.min(26, math.floor((ph - 200) / math.max(#scoring.reports, 1)))
    local ry = y + 70
    for _, r in ipairs(scoring.reports) do
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print(Scoring.seasonName(r.quarter):sub(1, 3):upper(), x + 30, ry)
        self:printFit('haul ' .. r.output .. '  food ' .. r.food .. '  logs ' .. r.logs .. '  gold ' .. r.gold .. '  hard ' .. r.complaints .. '  lost ' .. r.attrition .. '  grade ' .. r.grade,
            x + 90, ry + 2, pw - 110, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        ry = ry + rs
    end
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), ry + 20, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', ry + 66, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, ry + 66, self.fonts.hud, C.dim)
    end
    self:centeredFit((self.touch and 'tap' or 'ENTER or click') .. ': keep going, year after year     ' .. (self.touch and 'MENU up top for the title' or 'T: title'), y + ph - 36, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
end

return UI
