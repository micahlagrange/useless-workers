-- Screen space: bars, buttons, alerts, the season's tally, title and end screens.
require('src.constants')
local Util = require('src.util')
local Scoring = require('src.scoring')
local Campaign = require('src.campaign')

local UI = {}
UI.__index = UI

TOP_BAR_H = 40
BOTTOM_BAR_H = 80
FONT_PATH = 'assets/fonts/commodore64.ttf'
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

local function setColor(c) love.graphics.setColor(c[1], c[2], c[3], c[4] or 1) end

UI.FONT_SETS = {
    desk = { tiny = 10, small = 12, hud = 16, big = 26, title = 46 },
    touch = { tiny = 12, small = 14, hud = 18, big = 28, title = 44 },
}

function UI.new()
    local self = setmetatable({}, UI)
    -- The C64 face. It is wide, so every string has to be fitted to its
    -- box: tst/ui_overflow_test.lua draws every screen with its real glyph
    -- widths and fails on anything that spills. Two sets: the desk set, and
    -- a bigger one for fingers and small screens where 9 px is a smudge.
    self.fontSets = UI.FONT_SETS
    self.fontCache = {}
    self:useFonts('desk')
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
        wall = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        door = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        bridge = love.graphics.newImage('assets/images/ui/bridge_cursor.png'),
    }
    self.alerts = {}
    self.toastText, self.toastTtl = nil, 0
    self.unitButtons = {}
    self.buttons = {}
    self.topButtons = {}
    self.titleButtons = {}
    self.panelButtons = {}
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

function UI:useFonts(set)
    if self.fontSet == set then return end
    self.fontSet = set
    if not self.fontCache[set] then
        local f = {}
        for name, size in pairs(self.fontSets[set]) do
            f[name] = love.graphics.newFont(FONT_PATH, size)
            -- the game's default filter is nearest, for the pixel art; text
            -- drawn under the HUD's fractional scale needs linear or it
            -- drops and doubles pixel columns
            f[name]:setFilter('linear', 'linear')
        end
        self.fontCache[set] = f
    end
    self.fonts = self.fontCache[set]
end

function UI:layout(w, h)
    self.winW, self.winH = w, h
    local handheld = self.touch or h <= 500
    self:useFonts(handheld and 'touch' or 'desk')
    self.portrait = h > w * 1.2
    if self.portrait then
        -- a phone held upright: fit the width, the HUD stacks up
        self.scale = w / 420
    elseif handheld then
        -- a phone on its side or a small window: big type, bounded by width
        self.scale = math.min(h / 340, w / 760)
    else
        -- a desk: a 1000x620 design on the window's tighter side
        self.scale = math.min(w / 1000, h / 620)
    end
    self.scale = Util.clamp(self.scale, 0.6, 3.0)
    self.vw, self.vh = w / self.scale, h / self.scale
    local gap = 8
    local n = #ABILITY_ORDER
    -- quick buttons, for fingers and for people who forget keys. The top
    -- bar is one row: what does not fit folds away each frame, see drawTopBar.
    local defs = {
        { id = 'menu', label = 'MENU' }, { id = 'mute', label = 'MUTE' },
        { id = 'zoomin', label = '+' }, { id = 'zoomout', label = '-' },
        { id = 'follow', label = 'FOLLOW' }, { id = 'units', label = 'UNITS' }, { id = 'goal', label = 'GOAL' },
        { id = 'speed', label = 'SPEED 4x' },
    }
    if self.touch then
        -- fingers pinch to zoom; the + and - buttons only cost room
        for i = #defs, 1, -1 do
            if defs[i].id == 'zoomin' or defs[i].id == 'zoomout' then table.remove(defs, i) end
        end
    end
    self.quickH = handheld and 34 or 28
    self.quickPad = handheld and 24 or 16
    for _, d in ipairs(defs) do d.w = self.fonts.small:getWidth(d.label) + self.quickPad end
    self.quickDefs = defs
    self.narrow = self.vw < 980
    TOP_BAR_H = self.quickH + 12
    self.topButtons = {}
    self.dropButtons = {}
    self.dropdown = nil
    -- tool buttons along the bottom
    local th = handheld and 64 or 60
    self.buttons = {}
    self.panelW = 0
    self.goalBox = false
    if self.portrait then
        -- rows of four tools, an info strip (goals or the picked morphi) above
        local per = 4
        local rows = math.ceil(n / per)
        local bw = math.floor((self.vw - 32 - (per - 1) * gap) / per)
        self.infoH = 104
        BOTTOM_BAR_H = self.infoH + rows * (th + gap) + 10
        self.compactButtons = true
        for i, tool in ipairs(ABILITY_ORDER) do
            local r, c = math.floor((i - 1) / per), (i - 1) % per
            local by = self.vh - rows * (th + gap) - 10 + r * (th + gap) + gap
            self.buttons[i] = { tool = tool, x = 16 + c * (bw + gap), y = by, w = bw, h = th, key = tostring(i) }
        end
    else
        self.infoH = 0
        BOTTOM_BAR_H = th + 20
        self.goalBox = false
        -- the right side of the bar holds the goals or the picked morphi,
        -- as wide as the tools leave room for
        -- a tool button is at least as wide as its label in the small face
        local labelW = 0
        for _, tool in ipairs(ABILITY_ORDER) do labelW = math.max(labelW, self.fonts.tiny:getWidth(ABILITY_LABEL[tool])) end
        local minBtn = math.max(56, labelW + 12)
        local minTools = n * minBtn + (n - 1) * gap + 32
        local want = Util.clamp(math.floor(self.vw * 0.33), 260, 430)
        local room = self.vw - minTools - 16
        self.panelW = room >= 220 and math.min(want, room) or 0
        -- no room beside the tools: the goals float over the map's top right
        self.goalBox = self.panelW == 0
        local avail = self.vw - 32 - self.panelW - (self.panelW > 0 and 16 or 0) - (n - 1) * gap
        local bw = Util.clamp(math.floor(avail / n), minBtn, 120)
        self.compactButtons = bw < 100
        for i, tool in ipairs(ABILITY_ORDER) do
            self.buttons[i] = { tool = tool, x = 16 + (i - 1) * (bw + gap), y = self.vh - BOTTOM_BAR_H + 10, w = bw, h = th, key = tostring(i) }
        end
    end
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

-- Buttons on whatever panel is open: NEXT LEVEL, TRY AGAIN, CLOSE and so on.
function UI:panelButtonAt(mx, my)
    for _, b in ipairs(self.panelButtons) do
        if hit(b, mx, my) then return b.id end
    end
    return nil
end

function UI:panelButton(id, r, label, active, color)
    self:button(r, label, active, color)
    self.panelButtons[#self.panelButtons + 1] = { id = id, x = r.x, y = r.y, w = r.w, h = r.h }
end

-- A row of buttons centred at the bottom of a panel. defs = { {id, label, active, color} }
function UI:panelButtonRow(x, y, pw, ph, defs)
    local bw, bh, gap = math.min(200, math.floor((pw - 40) / #defs) - 12), 40, 12
    local total = #defs * bw + (#defs - 1) * gap
    local bx = x + math.floor(pw / 2 - total / 2)
    for _, d in ipairs(defs) do
        self:panelButton(d[1], { x = bx, y = y + ph - bh - 20, w = bw, h = bh }, d[2], d[3], d[4])
        bx = bx + bw + gap
    end
end

-- A box with a tick in it when done.
function UI:checkbox(x, y, s, done)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle('fill', x, y, s, s)
    setColor(done and C.good or C.dim)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, s - 1, s - 1)
    if done then
        love.graphics.setLineWidth(2)
        love.graphics.line(x + s * 0.22, y + s * 0.52, x + s * 0.42, y + s * 0.74, x + s * 0.8, y + s * 0.28)
        love.graphics.setLineWidth(1)
    end
end

-- A five point star, filled when earned.
function UI:star(cx, cy, r, filled)
    local pts = {}
    for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rad = (i % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = cx + math.cos(a) * rad
        pts[#pts + 1] = cy + math.sin(a) * rad
    end
    if filled then
        love.graphics.setColor(0.95, 0.8, 0.25)
        love.graphics.polygon('fill', pts)
        love.graphics.setColor(0.6, 0.45, 0.1)
    else
        setColor(C.dim)
    end
    love.graphics.polygon('line', pts)
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

-- The fonts from the given one down to the smallest.
function UI:fontsFrom(font)
    local order = { self.fonts.title, self.fonts.big, self.fonts.hud, self.fonts.small, self.fonts.tiny }
    local out, on = {}, false
    for _, f in ipairs(order) do
        if f == font then on = true end
        if on then out[#out + 1] = f end
    end
    return #out > 0 and out or { font }
end

-- One centred line in the given font, or a smaller one if it is too wide.
-- Returns the width and height it took.
function UI:centered(text, y, font, color, maxWidth)
    maxWidth = maxWidth or self.vw - 24
    local fonts = self:fontsFrom(font)
    local f = fonts[#fonts]
    for _, cand in ipairs(fonts) do
        if cand:getWidth(text) <= maxWidth then f = cand break end
    end
    self:printLine(text, (self.vw - maxWidth) / 2, y, maxWidth, 'center', color, { f })
    return math.min(f:getWidth(text), maxWidth), f:getHeight()
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

-- One line, never wrapped: the largest font that fits, else the smallest
-- with the end trimmed to '..'. For slots with something right under them.
function UI:printLine(text, x, y, maxWidth, align, color, fonts)
    fonts = fonts or { self.fonts.hud, self.fonts.small, self.fonts.tiny }
    local font = fonts[#fonts]
    for _, f in ipairs(fonts) do
        if f:getWidth(text) <= maxWidth then font = f break end
    end
    if font:getWidth(text) > maxWidth then
        while #text > 1 and font:getWidth(text .. '..') > maxWidth do text = text:sub(1, -2) end
        text = text:gsub('%s+$', '') .. '..'
    end
    setColor(color or C.text)
    love.graphics.setFont(font)
    local w = font:getWidth(text)
    local px = x
    if align == 'center' then px = x + (maxWidth - w) / 2 elseif align == 'right' then px = x + maxWidth - w end
    love.graphics.print(text, math.floor(px), y)
    return font:getHeight()
end

-- A paragraph: wrapped in the largest font that keeps it to maxLines.
-- Returns the height used.
function UI:printWrap(text, x, y, maxWidth, color, fonts, maxLines)
    fonts = fonts or { self.fonts.hud, self.fonts.small, self.fonts.tiny }
    local font = fonts[#fonts]
    for _, f in ipairs(fonts) do
        local _, l = f:getWrap(text, maxWidth)
        if #l <= (maxLines or 3) then font = f break end
    end
    local _, l = font:getWrap(text, maxWidth)
    setColor(color or C.text)
    love.graphics.setFont(font)
    love.graphics.printf(text, x, y, maxWidth, 'left')
    return font:getHeight() * #l
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

-- A wall from above: dark timber with the mortar lines showing.
function UI:iconWall(x, y, s)
    love.graphics.setColor(0.42, 0.31, 0.16)
    love.graphics.rectangle('fill', x + s * 0.06, y + s * 0.1, s * 0.88, s * 0.8)
    love.graphics.setColor(0.24, 0.17, 0.08)
    for i = 0, 2 do
        love.graphics.rectangle('fill', x + s * 0.06, y + s * (0.1 + 0.27 * i + 0.24), s * 0.88, s * 0.04)
    end
    love.graphics.rectangle('fill', x + s * 0.5, y + s * 0.1, s * 0.04, s * 0.24)
    love.graphics.rectangle('fill', x + s * 0.28, y + s * 0.37, s * 0.04, s * 0.24)
    love.graphics.rectangle('fill', x + s * 0.7, y + s * 0.37, s * 0.04, s * 0.24)
    love.graphics.rectangle('fill', x + s * 0.5, y + s * 0.64, s * 0.04, s * 0.26)
    love.graphics.setColor(0.6, 0.46, 0.26)
    love.graphics.rectangle('fill', x + s * 0.06, y + s * 0.1, s * 0.88, s * 0.04)
end

-- A door: a lighter plank in a dark frame, with a knob.
function UI:iconDoor(x, y, s)
    love.graphics.setColor(0.24, 0.17, 0.08)
    love.graphics.rectangle('fill', x + s * 0.18, y + s * 0.06, s * 0.64, s * 0.88)
    love.graphics.setColor(0.72, 0.56, 0.3)
    love.graphics.rectangle('fill', x + s * 0.26, y + s * 0.12, s * 0.48, s * 0.8)
    love.graphics.setColor(0.55, 0.42, 0.22)
    love.graphics.rectangle('fill', x + s * 0.49, y + s * 0.12, s * 0.03, s * 0.8)
    love.graphics.setColor(0.95, 0.85, 0.4)
    love.graphics.rectangle('fill', x + s * 0.62, y + s * 0.5, s * 0.08, s * 0.08)
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
    local fonts = r.h >= 52 and { self.fonts.big, self.fonts.hud, self.fonts.small } or { self.fonts.small, self.fonts.tiny }
    local f = fonts[#fonts]
    for _, cand in ipairs(fonts) do
        if cand:getWidth(label) <= r.w - 8 then f = cand break end
    end
    self:printLine(label, r.x, r.y + math.floor((r.h - f:getHeight()) / 2), r.w, 'center', color or (active and C.good or C.text), { f })
end

-- The values the top bar can show, most important first, each with its width.
function UI:topValues(game)
    local sc = game.scoring
    local hud = self.fonts.hud
    local arcade = game.mode == 'arcade'
    local out = {}
    local function pair(word, value, color) out[#out + 1] = { word = word, value = value, color = color } end
    local function icon(draw, value, color) out[#out + 1] = { icon = draw, value = value, color = color } end
    local qLabel = sc:seasonLabel():upper()
    if game.mode == 'level' then qLabel = 'LEVEL ' .. game.level.index end
    if arcade then qLabel = 'ARCADE ' .. game.level.index end
    local timeColor = C.text
    if not arcade and sc.quarterTimer <= 15 and math.floor(sc.quarterTimer * 2) % 2 == 0 then timeColor = C.warn end
    -- survival counts down; arcade has no clock, it just keeps time
    pair(qLabel, Util.formatTime(arcade and game.clock or sc.quarterTimer), timeColor)
    local key -- the one number a folded bar still shows
    if arcade then
        local ate, pop = Campaign.ateCount(game.workers), #game.level.def.morphis
        pair('ATE', ate .. '/' .. pop, ate >= pop and C.good or C.text)
        key = #out
        -- points only mean something in arcade; survival levels hand out none
        local spent, par = game.world.spent, game.level.def.par
        pair('PTS', spent .. '/' .. par, spent > par and C.warn or C.good)
    elseif game.mode == 'level' then
        key = 1
    end
    icon(UI.iconLog, tostring(game.world.stock.logs), C.good)
    local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
    icon(UI.iconFood, stored .. '/' .. cap, (cap == 0 and not arcade) and C.warn or C.text)
    icon(UI.iconMorphi, tostring(game.staffCount or 0))
    if not arcade then
        local fed = game.averageHunger and math.floor(game.averageHunger + 0.5) or 100
        pair('FED', fed .. '%', fed < 35 and C.warn or C.text)
        if game.mode == 'free' then key = #out end
    end
    icon(UI.iconGold, tostring(game.world.stock.gold), C.good)
    if not arcade then icon(UI.iconComplaint, tostring(sc.complaints), sc.complaints > 0 and C.warn or C.text) end
    if game.mode == 'free' then pair('HAUL', tostring(sc.output)) end
    for _, v in ipairs(out) do
        v.w = (v.icon and 22 + 6 or hud:getWidth(v.word) + 8) + hud:getWidth(v.value)
    end
    return out, out[key or 1]
end

-- One value at x, y. Returns its width.
function UI:drawTopValue(v, x, y)
    local hud = self.fonts.hud
    love.graphics.setFont(hud)
    if v.icon then
        v.icon(self, x, y - 3, 22)
        x = x + 28
    else
        setColor(C.dim)
        love.graphics.print(v.word, x, y)
        x = x + hud:getWidth(v.word) + 8
    end
    setColor(v.color or C.text)
    love.graphics.print(v.value, x, y)
    return v.w
end

local function drawCaret(x, y, open)
    if open then
        love.graphics.polygon('fill', x, y + 5, x + 10, y + 5, x + 5, y)
    else
        love.graphics.polygon('fill', x, y, x + 10, y, x + 5, y + 5)
    end
end

local function drawGear(cx, cy, r)
    for i = 0, 7 do
        local a = i * math.pi / 4
        local tx, ty = cx + math.cos(a) * r, cy + math.sin(a) * r
        love.graphics.rectangle('fill', math.floor(tx - 2), math.floor(ty - 2), 4, 4)
    end
    love.graphics.circle('fill', cx, cy, r - 1)
    love.graphics.setColor(0.16, 0.17, 0.14, 1)
    love.graphics.circle('fill', cx, cy, r * 0.4)
end

-- One row: the values on the left, the buttons on the right, PAUSE always
-- at the far right. Short of room the buttons fold under a gear first, then
-- the values fold into one button showing the number that matters most.
function UI:drawTopBar(game)
    setColor(C.bar)
    love.graphics.rectangle('fill', 0, 0, self.vw, TOP_BAR_H)
    local hud = self.fonts.hud
    local ty = math.floor((TOP_BAR_H - hud:getHeight()) / 2)
    local bh, by = self.quickH, 6
    local gapV = self.narrow and 16 or 26
    local values, key = self:topValues(game)
    local valuesW = 0
    for i, v in ipairs(values) do valuesW = valuesW + v.w + (i > 1 and gapV or 0) end
    local pauseW = self.fonts.small:getWidth('PAUSE') + 2 * self.quickPad
    local gearW = bh + 12
    local quickW = 0
    for _, d in ipairs(self.quickDefs) do quickW = quickW + d.w + 6 end
    local valuesBtnW = self.fonts.small:getWidth(key.word .. ' ' .. key.value) + 52
    local room = self.vw - 16 - 8 - pauseW - 6
    local foldButtons = valuesW + 20 + quickW > room
    local foldValues = foldButtons and valuesW + 20 + gearW + 6 > room
    self.foldValues, self.foldButtons = foldValues, foldButtons
    -- buttons, right to left
    self.topButtons = {}
    local x = self.vw - 8 - pauseW
    self.topButtons[#self.topButtons + 1] = { id = 'pause', label = 'PAUSE', x = x, y = by, w = pauseW, h = bh }
    x = x - 6
    if foldButtons then
        x = x - gearW
        self.topButtons[#self.topButtons + 1] = { id = 'gear', label = '', x = x, y = by, w = gearW, h = bh }
    else
        for _, d in ipairs(self.quickDefs) do
            x = x - d.w
            self.topButtons[#self.topButtons + 1] = { id = d.id, label = d.label, x = x, y = by, w = d.w, h = bh }
            x = x - 6
        end
    end
    local limit = x - 10
    -- values
    if foldValues then
        local label = key.word .. ' ' .. key.value
        local r = { id = 'values', label = label, x = 8, y = by, w = math.min(self.fonts.small:getWidth(label) + 52, limit - 8), h = bh }
        self.topButtons[#self.topButtons + 1] = r
        self:button({ x = r.x, y = r.y, w = r.w - 22, h = r.h }, label, self.dropdown == 'values', key.color)
        love.graphics.setColor(0.16, 0.17, 0.14, 1)
        love.graphics.rectangle('fill', r.x + r.w - 22, r.y, 22, r.h)
        setColor(C.dim)
        love.graphics.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
        drawCaret(r.x + r.w - 16, r.y + math.floor(r.h / 2) - 2, self.dropdown == 'values')
    else
        local vx = 16
        for _, v in ipairs(values) do
            vx = vx + self:drawTopValue(v, vx, ty) + gapV
        end
        -- following / seed, in whatever room is left before the buttons
        local right = ''
        if game.follow and game.selectedWorker then right = 'following ' .. game.selectedWorker.name end
        if limit - vx > 220 and game.mode == 'free' then right = right .. (right ~= '' and '   ' or '') .. 'seed ' .. tostring(game.seedString) end
        if right ~= '' and limit - vx > 60 then
            self:printLine(right, vx, ty + 2, limit - vx, 'right', C.dim, { self.fonts.small, self.fonts.tiny })
        end
    end
    for _, b in ipairs(self.topButtons) do
        if b.id ~= 'values' then
            local active = (b.id == 'follow' and game.follow) or (b.id == 'mute' and game.muted) or (b.id == 'pause' and game.paused)
            local label = b.label
            if b.id == 'speed' then
                label = 'SPEED ' .. (game.speed or 1) .. 'x'
                active = (game.speed or 1) > 1
            end
            if b.id == 'gear' then
                self:button(b, '', self.dropdown == 'gear')
                setColor(self.dropdown == 'gear' and C.good or C.text)
                drawGear(b.x + b.w / 2, b.y + b.h / 2, math.floor(bh * 0.3))
            else
                self:button(b, label, active)
            end
        end
    end
    self.topValuesCache = values
end

-- The open dropdown, under its button: every value, or every folded button.
function UI:drawDropdown(game)
    self.dropButtons = {}
    if self.dropdown == 'gear' and not self.foldButtons then self.dropdown = nil end
    if self.dropdown == 'values' and not self.foldValues then self.dropdown = nil end
    if self.dropdown == 'gear' then
        local w = 0
        for _, d in ipairs(self.quickDefs) do w = math.max(w, self.fonts.hud:getWidth(d.label) + 40) end
        w = math.min(math.max(w, 180), self.vw - 16)
        local bh = self.quickH + 8
        local gear
        for _, b in ipairs(self.topButtons) do if b.id == 'gear' then gear = b end end
        -- as many rows as the screen has room for, then another column
        local n = #self.quickDefs
        local rows = math.max(1, math.min(n, math.floor((self.vh - TOP_BAR_H - 16) / (bh + 6))))
        local cols = math.ceil(n / rows)
        rows = math.ceil(n / cols)
        w = math.min(w, math.floor((self.vw - 16 - (cols - 1) * 8) / cols))
        local totalW = cols * w + (cols - 1) * 8
        local x = math.max(8, math.min(gear.x + gear.w - totalW, self.vw - 8 - totalW))
        local y = TOP_BAR_H + 4
        local h = rows * (bh + 6) + 6
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', x - 6, y - 2, totalW + 12, h + 4)
        for i, d in ipairs(self.quickDefs) do
            local c, r0 = math.floor((i - 1) / rows), (i - 1) % rows
            local r = { id = d.id, x = x + c * (w + 8), y = y + 4 + r0 * (bh + 6), w = w, h = bh }
            local active = (d.id == 'follow' and game.follow) or (d.id == 'mute' and game.muted) or (d.id == 'speed' and (game.speed or 1) > 1)
            local label = d.id == 'speed' and ('SPEED ' .. (game.speed or 1) .. 'x') or d.label
            self:button(r, label, active)
            self.dropButtons[#self.dropButtons + 1] = r
        end
    elseif self.dropdown == 'values' then
        local values = self.topValuesCache or {}
        local rowH = self.fonts.hud:getHeight() + 12
        local w = 0
        for _, v in ipairs(values) do w = math.max(w, v.w + 32) end
        w = math.min(w, self.vw - 16)
        local x, y = 8, TOP_BAR_H + 4
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle('fill', x, y, w, #values * rowH + 8)
        setColor(C.accent)
        love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, #values * rowH + 7)
        for i, v in ipairs(values) do
            self:drawTopValue(v, x + 16, y + 4 + (i - 1) * rowH + 6)
        end
        self.dropButtons[#self.dropButtons + 1] = { id = 'values', x = x, y = y, w = w, h = #values * rowH + 8 }
    end
end

-- What a press hits in the open dropdown: a button id, 'inside', or nil.
function UI:dropdownAt(mx, my)
    for _, b in ipairs(self.dropButtons or {}) do
        if hit(b, mx, my) then return b.id == 'values' and 'inside' or b.id end
    end
    return nil
end

-- When a level is stuck, a loud button under the top bar's right end.
function UI:drawRestartCall(game)
    self.restartButton = nil
    if not game.suggestRestart then return end
    local label = self.touch and 'RESTART LEVEL' or 'RESTART LEVEL (R)'
    local bw = self.fonts.hud:getWidth(label) + 28
    local r = { x = self.vw - 8 - bw, y = (self.bannerBottom or TOP_BAR_H) + 8, w = bw, h = 40 }
    local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 5)
    love.graphics.setColor(C.warn[1] * pulse, C.warn[2] * pulse, C.warn[3] * pulse, 1)
    love.graphics.rectangle('fill', r.x, r.y, r.w, r.h)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    love.graphics.setFont(self.fonts.hud)
    love.graphics.setColor(0.08, 0.05, 0.04, 1)
    love.graphics.print(label, r.x + 14, r.y + 12)
    local why = 'Out of logs and nobody can reach food.'
    local f = self.fonts.small:getWidth(why) <= self.vw - 16 and self.fonts.small or self.fonts.tiny
    self:printLine(why, 8, r.y + r.h + 6, self.vw - 16, 'right', C.warn, { f })
    self.restartButton = r
    self.restartBottom = r.y + r.h + 6 + f:getHeight()
end

function UI:restartButtonAt(mx, my)
    return hit(self.restartButton, mx, my)
end

function UI:drawAlerts(game)
    love.graphics.setFont(self.fonts.small)
    local y = (self.bannerBottom or TOP_BAR_H) + 8
    local box = game and self:goalBoxRect(game)
    local maxW = (box and box.x - 16 or self.vw) - 40
    local bottom = self.vh - BOTTOM_BAR_H - 70 -- the toast lives below this
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        local _, lines = self.fonts.small:getWrap(a.text, maxW)
        local h = #lines * self.fonts.small:getHeight() + 6
        if y + h > bottom then break end
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
    elseif tool == ABILITY_WALL then self:iconWall(x, y, size)
    elseif tool == ABILITY_DOOR then self:iconDoor(x, y, size)
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
    -- one label size for the whole bar: the largest every label fits in
    local labelFont = self.fonts.tiny
    local b1 = self.buttons[1]
    if b1 and not self.compactButtons then
        local room = b1.w - 5 - 26 - 4 - 4
        if not self.touch then room = room - self.fonts.tiny:getWidth('7') - 6 end -- the key number
        for _, f in ipairs({ self.fonts.hud, self.fonts.small }) do
            local fits = true
            for _, b in ipairs(self.buttons) do
                if f:getWidth(ABILITY_LABEL[b.tool]) > room then fits = false break end
            end
            if fits then labelFont = f break end
        end
    end
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
            self:printLine(ABILITY_LABEL[b.tool], b.x, b.y + 32, b.w, 'center', affordable and C.text or C.dim, { self.fonts.tiny })
            self:printLine(self:fitLine(abilities:costText(b.tool), b.w - 4), b.x, b.y + 44, b.w, 'center', C.dim, { self.fonts.tiny })
        else
            local IS = 26
            self:drawToolIcon(b.tool, b.x + 5, b.y + 8, IS, affordable)
            local lx = b.x + 5 + IS + 4
            local room = b.x + b.w - lx - 4
            -- the key number sits in the corner when the label leaves it room
            local keyW = self.fonts.tiny:getWidth(b.key) + 6
            local label = ABILITY_LABEL[b.tool]
            local showKey = not self.touch and labelFont:getWidth(label) <= room - keyW
            local labelFonts = { labelFont, self.fonts.tiny }
            self:printLine(label, lx, b.y + 8, showKey and room - keyW or room, 'left', affordable and C.text or C.dim, labelFonts)
            self:printLine(self:fitLine(abilities:costText(b.tool), room), lx, b.y + 30, room, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            if showKey then
                love.graphics.setFont(self.fonts.tiny)
                setColor(C.dim)
                love.graphics.print(b.key, b.x + b.w - 4 - self.fonts.tiny:getWidth(b.key), b.y + 3)
            end
        end
    end
    -- right side: selected worker or hints
    local w = game.selectedWorker
    if self.portrait then
        -- the strip above the tools
        local ix, iy, iw = 16, self.vh - BOTTOM_BAR_H + 8, self.vw - 32
        if w and w.alive then
            local lh = self.fonts.small:getHeight() + 8
            self:printLine(w.name .. ', the ' .. w.species .. ', ' .. w.roleInfo.label:lower(), ix, iy, iw, 'left', C.good, { self.fonts.hud, self.fonts.small })
            self:printLine(w:describeState(), ix, iy + lh + 4, iw, 'left', C.text, { self.fonts.small, self.fonts.tiny })
            local status = w.arcade and (w.ate and 'has eaten' or 'not eaten yet')
                or ('hunger ' .. math.floor(w.hunger + 0.5) .. '%, ' .. w:mood())
            self:printLine(status, ix, iy + 2 * lh + 4, iw, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        elseif game.mode == 'arcade' then
            self:drawGoalList(game, ix, iy, iw, 20, self.infoH - 12)
        else
            local ly = iy
            for _, line in ipairs({ 'Drag to pan, tap to pick, pinch to zoom.', 'Pick a tool below, then tap the map.' }) do
                ly = ly + self:printLine(line, ix, ly, iw, 'left', C.dim, { self.fonts.small, self.fonts.tiny }) + 6
            end
        end
    elseif self.panelW > 0 then
        local pw = self.panelW
        local px = self.vw - pw - 16
        local py = self.vh - BOTTOM_BAR_H + 8
        if w and w.alive then
            love.graphics.setFont(self.fonts.hud)
            setColor(C.good)
            love.graphics.print(w.name, px, py)
            local nx = px + self.fonts.hud:getWidth(w.name) + 10
            self:printLine('the ' .. w.species .. ', ' .. w.roleInfo.label:lower() .. ', eats', nx, py + 3, px + pw - 160 - 6 - nx, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            self:iconFoodKind(w.diet, px + pw - 160, py - 2, 18)
            self:printLine(w:describeState(), px, py + 22, pw - 150, 'left', C.text, { self.fonts.small, self.fonts.tiny })
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
            self:printLine('hauled ' .. w.delivered .. '  hardships ' .. w.complaintCount, sx + 6, py + 46, pw - 150 - 66, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            local bx = px + pw - 140
            setColor(C.dim)
            love.graphics.setFont(self.fonts.tiny)
            if w.arcade then
                love.graphics.print('MEAL', bx, py + 22)
                self:printLine(w.ate and 'eaten' or 'not yet', bx, py + 36, 140, 'left', w.ate and C.good or C.warn, { self.fonts.small, self.fonts.tiny })
                self:printLine('JOB ' .. w.roleInfo.label:lower(), bx, py + 52, 140, 'left', C.dim, { self.fonts.tiny })
            else
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
            end
        elseif game.mode == 'arcade' then
            -- the live checklist: what the band insists on before eating
            self:drawGoalList(game, px, self.vh - BOTTOM_BAR_H + 6, pw, 15, BOTTOM_BAR_H - 10)
        else
            local lines
            if self.touch then
                lines = {
                    'Drag to pan, tap to pick, pinch to zoom.',
                    'Pick a tool below, then tap the map.',
                }
            else
                lines = {
                    'Drag or WASD to pan, wheel to zoom, 1-6 pick a tool.',
                    'Click a morphi with SELECT to see what it is up to.',
                }
            end
            local ly = py + 4
            for _, line in ipairs(lines) do
                ly = ly + self:printLine(line, px, ly, pw, 'left', C.dim, { self.fonts.small, self.fonts.tiny }) + 4
            end
        end
    elseif w and w.alive then
        -- narrow: one line above the bar
        local line = w.name .. ': ' .. w:describeState() .. (w.arcade and (w.ate and '  (eaten)' or '') or ('  hunger ' .. math.floor(w.hunger + 0.5) .. '%  ' .. w:mood()))
        local ty = self.vh - BOTTOM_BAR_H - 22
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', 8, ty, self.vw - 16, 20)
        self:printLine(line, 14, ty + 4, self.vw - 28, 'left', C.text, { self.fonts.small, self.fonts.tiny })
    end
    if self.toastText then
        local f = self.fonts.tiny
        for _, cand in ipairs({ self.fonts.hud, self.fonts.small }) do
            if cand:getWidth(self.toastText) <= self.vw - 56 then f = cand break end
        end
        local tw = math.min(f:getWidth(self.toastText) + 20, self.vw - 16)
        local tx = self.vw / 2 - tw / 2
        local th = f:getHeight() + 12
        local ty = self.vh - BOTTOM_BAR_H - th - 14
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', tx, ty, tw, th)
        self:printLine(self.toastText, tx + 10, ty + 6, tw - 20, 'left', C.warn, { f })
        love.graphics.setFont(self.fonts.hud)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The arcade checklist with its ticks. Rows shrink to fit maxH when given.
-- Returns the height used.
function UI:drawGoalList(game, x, y, w, rowH, maxH)
    local goals = Campaign.goals(game.level, game.workers)
    if maxH and #goals > 0 then rowH = math.min(rowH, math.floor(maxH / #goals)) end
    local ly = y
    local box = rowH - 4
    for _, g in ipairs(goals) do
        self:checkbox(x, ly + 1, box, g.done)
        self:printLine(g.label, x + box + 8, ly + math.floor((box - self.fonts.small:getHeight()) / 2) + 1, w - box - 8, 'left', g.done and C.good or C.text, { self.fonts.small, self.fonts.tiny })
        ly = ly + rowH
    end
    return ly - y
end

-- Paused: a banner under the top bar. The world is stopped, the tools are not.
function UI:drawPauseBanner(game)
    if not game.paused then return end
    local text = self.touch and 'PAUSED - tap PAUSE to carry on' or 'PAUSED - SPACE to carry on'
    local f = self.fonts.tiny
    for _, cand in ipairs({ self.fonts.hud, self.fonts.small }) do
        if cand:getWidth(text) <= self.vw - 60 then f = cand break end
    end
    local w, h = math.min(f:getWidth(text) + 32, self.vw - 16), f:getHeight() + 14
    self.bannerBottom = TOP_BAR_H + 8 + h
    local x, y = math.floor(self.vw / 2 - w / 2), TOP_BAR_H + 8
    local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 4)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle('fill', x, y, w, h)
    love.graphics.setColor(C.accent[1] * pulse, C.accent[2] * pulse, C.accent[3] * pulse, 1)
    love.graphics.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
    self:printLine(text, x + 16, y + 7, w - 32, 'center', C.good, { f })
end

-- Arcade goals over the map's top right, when the bar has no room for them.
function UI:goalBoxRect(game)
    if not (self.goalBox and game.mode == 'arcade') then return nil end
    local goals = #Campaign.goals(game.level, game.workers)
    local w = math.min(math.floor(self.vw * 0.45), 360)
    local rowH = self.fonts.small:getHeight() + 6
    local y = ((game.suggestRestart and self.restartBottom) or (game.paused and self.bannerBottom) or TOP_BAR_H) + 8
    return { x = self.vw - w - 8, y = y, w = w, h = goals * rowH + 10, rowH = rowH }
end

function UI:drawGoalBox(game)
    local r = self:goalBoxRect(game)
    if not r then return end
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle('fill', r.x, r.y, r.w, r.h)
    self:drawGoalList(game, r.x + 8, r.y + 6, r.w - 16, r.rowH)
end

function UI:drawHUD(game)
    self.bannerBottom = TOP_BAR_H
    self:drawTopBar(game)
    self:drawPauseBanner(game)
    self:drawRestartCall(game)
    self:drawGoalBox(game)
    self:drawAlerts(game)
    self:drawBottomBar(game)
    self:drawDropdown(game)
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
    local compact = pw < 640 -- a phone: picture, name, task and the button
    local rowH = Util.clamp(math.floor((self.vh - 120) / math.max(#units, 1)), 30, 54)
    local ph = 74 + #units * rowH + 16
    local x, y
    x, y, pw, ph = self:panel(pw, ph)
    self.unitPanel = { x = x, y = y, w = pw, h = ph }
    local btnW = compact and 100 or 120
    self:printLine('UNITS  (' .. #units .. ' morphis)', x + 18, y + 16, pw - btnW - 52, 'left', C.text, { self.fonts.big, self.fonts.hud, self.fonts.small })
    local cName = x + 18 + rowH
    local cTask = compact and x + math.floor(pw * 0.42) or x + math.floor(pw * 0.34)
    local cHunger, cMorale = x + math.floor(pw * 0.62), x + math.floor(pw * 0.76)
    local right = x + pw - btnW - 24
    local wide = pw >= 760
    local arcade = game.mode == 'arcade'
    self:printLine('MORPHI', cName, y + 56, cTask - cName - 8, 'left', C.dim, { self.fonts.tiny })
    self:printLine('TASK', cTask, y + 56, (compact and right or cHunger) - cTask - 8, 'left', C.dim, { self.fonts.tiny })
    if not compact then
        self:printLine(arcade and 'MEAL' or 'HUNGER', cHunger, y + 56, (wide and not arcade and cMorale or right) - cHunger - 8, 'left', C.dim, { self.fonts.tiny })
        if wide and not arcade then self:printLine('MORALE', cMorale, y + 56, right - cMorale - 8, 'left', C.dim, { self.fonts.tiny }) end
    end
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
        local nameFonts = rowH >= 44 and { self.fonts.hud, self.fonts.small, self.fonts.tiny } or { self.fonts.small, self.fonts.tiny }
        local nameW = cTask - cName - 30
        self:printLine(w.name, cName, ry + 4, nameW, 'left', C.good, nameFonts)
        local nf = love.graphics.getFont()
        self:iconFoodKind(w.diet, cName + math.min(nf:getWidth(w.name), nameW) + 6, ry + 2, 16)
        if rowH >= 44 then
            self:printLine(w.species .. ', ' .. w.roleInfo.label:lower(), cName, ry + 26, cTask - cName - 8, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        end
        local taskRight = compact and right or cHunger
        self:printLine(w:describeState(), cTask, ry + 8, taskRight - cTask - 10, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        if not compact then
            local barW = (wide and not arcade and cMorale or right) - cHunger - 12
            if arcade then
                self:printLine(w.ate and 'eaten' or 'not yet', cHunger, ry + 8, barW, 'left', w.ate and C.good or C.warn, { self.fonts.small, self.fonts.tiny })
            else
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.rectangle('fill', cHunger, ry + 10, barW, 10)
                local frac = w.hunger / HUNGER_MAX
                if frac > 0.6 then setColor(C.good)
                elseif frac > HUNGER_EAT_THRESHOLD / HUNGER_MAX then love.graphics.setColor(0.95, 0.75, 0.3)
                else setColor(C.warn) end
                love.graphics.rectangle('fill', cHunger, ry + 10, barW * frac, 10)
                if rowH >= 40 then
                    self:printLine(math.floor(w.hunger + 0.5) .. '%', cHunger, ry + 24, barW, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
                end
            end
            if wide and not arcade then
                local mw = right - cMorale - 12
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.rectangle('fill', cMorale, ry + 10, mw, 10)
                local mf = w.morale / MORALE_MAX
                if mf > 0.6 then setColor(C.good) elseif mf > MORALE_LOW / MORALE_MAX then love.graphics.setColor(0.95, 0.75, 0.3) else setColor(C.warn) end
                love.graphics.rectangle('fill', cMorale, ry + 10, mw * mf, 10)
                if rowH >= 40 then
                    self:printLine(w:mood(), cMorale, ry + 24, mw, 'left', mf > MORALE_LOW / MORALE_MAX and C.dim or C.warn, { self.fonts.small, self.fonts.tiny })
                end
            end
        end
        local following = game.follow and selected
        local r = { x = x + pw - btnW - 18, y = ry + math.floor((rowH - 4 - 28) / 2), w = btnW, h = 28 }
        self:button(r, following and 'FOLLOWING' or 'FOLLOW', following)
        self.unitButtons[#self.unitButtons + 1] = { worker = w, x = r.x, y = r.y, w = r.w, h = r.h }
        ry = ry + rowH
    end
    self:panelButton('close', { x = x + pw - btnW - 18, y = y + 12, w = btnW, h = 30 }, 'CLOSE', false)
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
    self.panelButtons = {}
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
    local gradeW = self.fonts.title:getWidth('F') + 40
    local lx = x + math.floor(pw * 0.06)
    local vx = x + math.floor((pw - gradeW) * 0.62)
    for _, row in ipairs(rows) do
        if row[3] then row[3](self, lx, ry - 3, 20) end
        self:printLine(row[1], lx + 30, ry, vx - lx - 30 - 10, 'left', C.dim, { self.fonts.hud, self.fonts.small, self.fonts.tiny })
        self:printLine(row[2], vx, ry, x + pw - gradeW - vx - 10, 'left', C.text, { self.fonts.hud, self.fonts.small, self.fonts.tiny })
        ry = ry + rs
    end
    local gradeColor = C.good
    if report.grade == 'F' or report.grade == 'C' then gradeColor = C.warn end
    love.graphics.setFont(self.fonts.title)
    setColor(gradeColor)
    love.graphics.print(report.grade, x + pw - gradeW + 10, y + 70 + rs)
    self:panelButtonRow(x, y, pw, ph, { { 'next', scoring:yearComplete() and 'THE YEAR ENDS' or 'NEXT SEASON', true } })
end

function UI:drawTitle(title, highScore)
    love.graphics.setColor(0.09, 0.1, 0.08, 1)
    love.graphics.rectangle('fill', 0, 0, self.vw, self.vh)
    self.titleButtons = {}
    local cx = self.vw / 2
    local short = self.vh < 520
    local g = self.vh / 800            -- gaps shrink on short screens
    local function gap(px) return math.floor(px * g) end
    local mh = self.touch and 34 or 28
    self.titleButtons.mute = { x = self.vw - 90, y = 10, w = 80, h = mh }
    -- the name keeps clear of MUTE in the corner
    local y = math.max(gap(40), 10)
    local _, th = self:centered('MORPHIS', y, self.fonts.title, C.text, self.vw - 2 * 100)
    y = y + th + gap(14)
    if not short then
        y = y + self:centeredFit('A small band settling the harsh wilds.', y, self.vw - 24, C.dim, { self.fonts.hud, self.fonts.small }) + 2
        y = y + self:centeredFit('They will look after themselves. Badly.', y, self.vw - 24, C.dim, { self.fonts.hud, self.fonts.small }) + gap(36)
    else
        y = y + 6
    end
    -- what to play: a level, or the open wilds, between two arrows
    local opt = title.options[title.option]
    local row1
    if opt.kind == 'level' then
        row1 = Campaign.title[opt.set] .. ' ' .. opt.index .. ': ' .. (opt.locked and 'LOCKED' or opt.def.name:upper())
    else
        row1 = 'FREE PLAY'
    end
    local aw, ah = 44, 40
    local nw, nh = self:centered(row1, y + 6, self.fonts.big, opt.locked and C.dim or C.text, self.vw - 2 * (aw + 20) - 16)
    self.titleButtons.left = { x = math.floor(cx - nw / 2 - 12 - aw), y = y - 1, w = aw, h = ah }
    self.titleButtons.right = { x = math.floor(cx + nw / 2 + 12), y = y - 1, w = aw, h = ah }
    self:button(self.titleButtons.left, '<', false)
    self:button(self.titleButtons.right, '>', false)
    y = y + ah + 14 -- clear of the arrows above
    local function diffRow(name)
        local dw, dh = self:centered(name, y, self.fonts.hud, C.text, self.vw - 2 * (36 + 16) - 16)
        self.titleButtons.diffLeft = { x = math.floor(cx - dw / 2 - 12 - 36), y = y - 8, w = 36, h = 30 }
        self.titleButtons.diffRight = { x = math.floor(cx + dw / 2 + 12), y = y - 8, w = 36, h = 30 }
        self:button(self.titleButtons.diffLeft, '<', false)
        self:button(self.titleButtons.diffRight, '>', false)
        y = y + 26 -- clear of the arrow buttons
    end
    local diff = DIFFICULTIES[title.difficultyIndex]
    if opt.kind == 'level' then
        if opt.locked then
            local _, h = self:centered('clear ' .. Campaign.title[opt.set]:lower() .. ' level ' .. (opt.index - 1) .. ' first', y, self.fonts.small, C.dim)
            y = y + h + gap(30)
        else
            y = y + self:centeredFit(opt.def.blurb, y, self.vw - 40, C.dim, { self.fonts.small, self.fonts.tiny }) + 4
            local points = Campaign.points(opt.def, opt.set, title.arcadeDifficulty)
            local best = opt.best and ('   best ' .. opt.best .. (opt.best <= opt.def.par and ' (3 stars)' or '')) or ''
            local _, h = self:centered(points .. ' points to spend, par ' .. opt.def.par .. best, y, self.fonts.small, C.text)
            y = y + h + 4 + gap(16)
            if opt.set == 'arcade' then
                local ad = ARCADE_DIFFICULTIES[title.arcadeDifficulty]
                diffRow(ad.name:upper())
                y = y + self:centeredFit(ad.blurb, y, self.vw - 24, C.dim, { self.fonts.small, self.fonts.tiny })
            end
            y = y + gap(20)
        end
    else
        diffRow(diff.name:upper())
        y = y + self:centeredFit(diff.workers .. ' settlers, hunger ' .. diff.drain .. '/s, score x' .. diff.multiplier .. ', seasons and migrants', y, self.vw - 24, C.dim, { self.fonts.small, self.fonts.tiny }) + gap(30)
        local seedText = 'SEED: ' .. title.seed
        if title.editingSeed then seedText = seedText .. (math.floor(love.timer.getTime() * 2) % 2 == 0 and '_' or ' ') end
        local sw = self:centered(seedText, y, self.fonts.big, title.editingSeed and C.good or C.text)
        self.titleButtons.seed = { x = cx - (sw + 40) / 2, y = y - 8, w = sw + 40, h = 42 }
        y = y + 34
        if title.editingSeed and self.touch then
            -- phones will not raise a keyboard for love.js: here is one
            self:drawSeedKeyboard(y + 4)
            self:button(self.titleButtons.mute, title.muted and 'UNMUTE' or 'MUTE', title.muted)
            return
        end
        local hint = title.editingSeed and 'type a seed, then press ENTER' or (self.touch and 'tap the seed to change it' or 'tap or press S to change the seed')
        local _, h2 = self:centered(hint, y, self.fonts.small, C.dim)
        y = y + h2 + gap(24)
        local _, h3 = self:centered('HIGH SCORE (' .. diff.name .. '): ' .. tostring(highScore), y, self.fonts.hud)
        y = y + h3
    end
    y = y + gap(30)
    local stw = math.min(self.vw - 40, math.max(260, self.fonts.big:getWidth('START') + 80))
    self.titleButtons.start = { x = cx - stw / 2, y = y, w = stw, h = 54 }
    love.graphics.setColor(0.2, 0.24, 0.14, 1)
    love.graphics.rectangle('fill', self.titleButtons.start.x, y, stw, 54)
    setColor(C.accent)
    love.graphics.rectangle('line', self.titleButtons.start.x + 0.5, y + 0.5, stw - 1, 53)
    self:centered('START', y + 14, self.fonts.big, C.good)
    y = y + 54 + gap(14)
    -- the small print, as much of it as there is room for
    local notes = {
        'ARCADE: every morphi wants one meal. Give the band what it insists on, spend as few points as you can.',
        'SURVIVAL (retired): keep everyone fed to the clock. You never control a morphi.',
    }
    if not self.touch then table.insert(notes, 1, 'arrow keys pick the level and the difficulty') end
    for _, note in ipairs(notes) do
        local fonts = { self.fonts.small, self.fonts.tiny }
        local f = self.fonts.tiny
        for _, cand in ipairs(fonts) do
            if cand:getWidth(note) <= self.vw - 40 then f = cand break end
        end
        local _, lines = f:getWrap(note, self.vw - 40)
        local h = #lines * f:getHeight()
        if y + h > self.vh - 6 then break end
        y = y + self:centeredFit(note, y, self.vw - 40, C.dim, fonts) + 6
    end
    self:button(self.titleButtons.mute, title.muted and 'UNMUTE' or 'MUTE', title.muted)
end

-- Letters and digits for the seed, DEL and OK. Keys are title buttons
-- named 'key:<char>'.
function UI:drawSeedKeyboard(y)
    local rows = { 'ABCDEFGHIJ', 'KLMNOPQRST', 'UVWXYZ0123', '456789' }
    local gap = 6
    local kw = math.floor((self.vw - 24 - 9 * gap) / 10)
    local kh = Util.clamp(math.floor((self.vh - y - 12) / #rows) - gap, 26, 48)
    local x0 = math.floor((self.vw - (10 * kw + 9 * gap)) / 2)
    for r, row in ipairs(rows) do
        local ky = y + (r - 1) * (kh + gap)
        for i = 1, #row do
            local ch = row:sub(i, i)
            local b = { x = x0 + (i - 1) * (kw + gap), y = ky, w = kw, h = kh }
            self.titleButtons['key:' .. ch] = b
            self:button(b, ch, false)
        end
        if r == #rows then
            -- DEL and OK fill the rest of the last row
            local left = x0 + #row * (kw + gap)
            local rest = x0 + 10 * kw + 9 * gap - left
            local dw = math.floor((rest - gap) / 2)
            local del = { x = left, y = ky, w = dw, h = kh }
            local ok = { x = left + dw + gap, y = ky, w = rest - dw - gap, h = kh }
            self.titleButtons['key:DEL'] = del
            self.titleButtons['key:OK'] = ok
            self:button(del, 'DEL', false)
            self:button(ok, 'OK', true)
        end
    end
end

function UI:drawLevelClear(game)
    local lv = game.level
    local last = lv.index >= #game.levels
    local x, y, pw, ph = self:panel(720, last and 350 or 320)
    self:centeredFit(Campaign.title[lv.set] .. ' ' .. lv.index .. ' CLEAR: ' .. lv.def.name:upper(), y + 28, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    for i = 1, 3 do
        self:star(x + pw / 2 + (i - 2) * 64, y + 100, 24, i <= lv.stars)
    end
    local spent, par = game.world.spent, lv.def.par
    self:centeredFit('spent ' .. spent .. ' point' .. (spent == 1 and '' or 's') .. ', par ' .. par, y + 150, pw - 40, C.text, { self.fonts.hud })
    if spent > par then
        self:centeredFit('A sharper eye spends ' .. par .. '. Look for the narrow crossing, the thin stone, the nook.', y + 180, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    elseif spent < par then
        self:centeredFit('UNDER PAR. Sharper than we planned for.', y + 180, pw - 40, C.good, { self.fonts.hud, self.fonts.small })
    else
        self:centeredFit('Right on par.', y + 180, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    end
    if lv.isNewBest then self:centered('NEW BEST', y + 215, self.fonts.hud, C.good) end
    if not last then
        self:panelButtonRow(x, y, pw, ph, { { 'next', 'NEXT LEVEL', true }, { 'title', 'TITLE', false } })
    else
        self:centeredFit('All ' .. #game.levels .. ' levels clear.', y + 250, pw - 40, C.text, { self.fonts.hud })
        self:panelButtonRow(x, y, pw, ph, { { 'title', 'TITLE', true } })
    end
end

-- What this level asks for. Opens paused at the start and from GOAL up top.
function UI:drawGoal(game)
    if game.mode == 'arcade' then return self:drawArcadeGoal(game) end
    local title, lines
    if game.mode == 'level' then
        local def = game.level.def
        title = 'LEVEL ' .. game.level.index .. ': ' .. def.name:upper()
        lines = {
            { def.intro, C.text },
            { 'Keep everyone fed until the clock runs out. Nobody may be lost.', C.text },
            { def.points .. ' points to spend, par ' .. def.par .. '. Bridges, bins and beds cost points. Mining is free. Logs are points.', C.dim },
        }
    else
        title = 'FREE PLAY'
        lines = {
            { 'A random map, four seasons, migrants when the haul is good.', C.text },
            { 'Keep the band fed. Hardships and hunger wear morale down; at zero a morphi leaves.', C.text },
            { 'Mark FLOOR spots or BINS so foragers can store food, MINE stone, BRIDGE the rivers.', C.dim },
        }
    end
    local eaters, seen = {}, {}
    for _, w in ipairs(game.workers) do
        if w.alive and not seen[w.sheet] then
            seen[w.sheet] = true
            eaters[#eaters + 1] = { label = w.species .. ' eats ' .. w.diet, diet = w.diet }
        end
    end
    local pw = math.min(760, self.vw - 16)
    local inner = pw - 48
    local small = self.fonts.small
    local function eaterRows()
        local rows, cx = 1, 0
        for _, e in ipairs(eaters) do
            local lw = small:getWidth(e.label) + 26
            if cx > 0 and cx + lw > inner then rows, cx = rows + 1, 0 end
            cx = cx + lw + 16
        end
        return rows
    end
    -- the largest body font that keeps the panel on screen
    local function height(f)
        local h = 64
        for _, line in ipairs(lines) do
            local _, l = f:getWrap(line[1], inner)
            h = h + #l * f:getHeight() + 10
        end
        return h + 6 + 18 + eaterRows() * 24 + 10 + 60
    end
    local body = self.fonts.tiny
    for _, f in ipairs({ self.fonts.hud, small, self.fonts.tiny }) do
        if height(f) <= self.vh - 16 then body = f break end
    end
    local x, y, ph
    x, y, pw, ph = self:panel(pw, height(body))
    self:centeredFit(title, y + 22, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    local ly = y + 64
    for _, line in ipairs(lines) do
        ly = ly + self:printWrap(line[1], x + 24, ly, inner, line[2], { body }, 99) + 10
    end
    -- who eats what
    ly = ly + 6
    self:printLine('WHO EATS WHAT', x + 24, ly, inner, 'left', C.dim, { small, self.fonts.tiny })
    ly = ly + 18
    local cx = 0
    for _, e in ipairs(eaters) do
        local lw = small:getWidth(e.label) + 26
        if cx > 0 and cx + lw > inner then cx = 0; ly = ly + 24 end
        self:iconFoodKind(e.diet, x + 24 + cx, ly - 3, 18)
        self:printLine(e.label, x + 24 + cx + 22, ly, inner - cx - 22, 'left', C.text, { small, self.fonts.tiny })
        cx = cx + lw + 16
    end
    self:panelButtonRow(x, y, pw, ph, { { 'close', game.started and 'BACK TO IT' or 'BEGIN', true } })
end

function UI:drawArcadeGoal(game)
    local def = game.level.def
    local pw = math.min(760, self.vw - 16)
    local inner = pw - 48
    local small = self.fonts.small
    local points = game.level.points
    local diff = ARCADE_DIFFICULTIES[game.level.difficulty or DEFAULT_ARCADE_DIFFICULTY]
    local costs = points .. ' points to spend on ' .. diff.name:lower() .. ', par ' .. def.par .. '. Bins, walls, doors and bridge tiles cost a log each. Floors and mining are free.'
    if points == 0 then costs = 'Nothing to spend and nothing to build. Just watch.' end
    local footer = 'GOAL up top brings this back, SPEED fast forwards, MENU starts the level over.'
    local band = {}
    for _, w in ipairs(game.workers) do
        if w.alive then band[#band + 1] = w.species .. ' the ' .. w.roleInfo.label:lower() end
    end
    -- Measure first, so the panel fits its content: everything but the intro,
    -- then the intro in the largest font (three lines at most) that still
    -- keeps the panel on screen.
    local function wrapH(text, fonts, maxLines)
        for i, f in ipairs(fonts) do
            local _, lines = f:getWrap(text, inner)
            if #lines <= maxLines or i == #fonts then return #lines * f:getHeight(), f end
        end
    end
    local costsH = wrapH(costs, { small, self.fonts.tiny }, 2)
    local footerH = wrapH(footer, { small, self.fonts.tiny }, 1)
    local bandRows, cx = 1, 0
    for _, label in ipairs(band) do
        local lw = small:getWidth(label)
        if cx > 0 and cx + lw > inner then bandRows, cx = bandRows + 1, 0 end
        cx = cx + lw + 22
    end
    local goals = #Campaign.goals(game.level, game.workers)
    local showFooter, showCosts, showBand = true, true, true
    local function restH()
        return 64 + 10 + 18 + goals * 22 + 6 + (showCosts and costsH + 10 or 0)
            + (showBand and 18 + bandRows * 18 + 12 or 0) + (showFooter and footerH + 10 or 0) + 60
    end
    local function pickIntro()
        local font, h
        for _, f in ipairs({ self.fonts.hud, small, self.fonts.tiny }) do
            local _, lines = f:getWrap(def.intro, inner)
            font, h = f, #lines * f:getHeight()
            if #lines <= 3 and restH() + h <= self.vh - 16 then return font, h, true end
        end
        return font, h, false
    end
    -- a short screen loses the footer first, then the costs line (the top
    -- bar shows the points anyway)
    local introFont, introH, fits = pickIntro()
    if not fits then showFooter = false; introFont, introH, fits = pickIntro() end
    if not fits then showCosts = false; introFont, introH, fits = pickIntro() end
    if not fits then showBand = false; introFont, introH = pickIntro() end -- UNITS lists them
    local rest = restH()
    local x, y, ph
    x, y, pw, ph = self:panel(pw, rest + introH)
    self:centeredFit('ARCADE ' .. game.level.index .. ': ' .. def.name:upper(), y + 22, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    local ly = y + 64
    ly = ly + self:printWrap(def.intro, x + 24, ly, inner, C.text, { introFont }) + 10
    love.graphics.setFont(small)
    setColor(C.dim)
    love.graphics.print('THE BAND INSISTS ON', x + 24, ly)
    ly = ly + 18
    ly = ly + self:drawGoalList(game, x + 24, ly, inner, 22) + 6
    if showCosts then ly = ly + self:printWrap(costs, x + 24, ly, inner, C.dim, { small, self.fonts.tiny }, 2) + 10 end
    if showBand then
        love.graphics.setFont(small)
        setColor(C.dim)
        love.graphics.print('THE BAND', x + 24, ly)
        ly = ly + 18
        cx = 0
        for _, label in ipairs(band) do
            local lw = small:getWidth(label)
            if cx > 0 and cx + lw > inner then cx = 0; ly = ly + 18 end
            love.graphics.setFont(small)
            setColor(C.text)
            love.graphics.print(label, x + 24 + cx, ly)
            cx = cx + lw + 22
        end
        ly = ly + 18 + 12
    end
    if showFooter then self:centeredFit(footer, ly, inner, C.dim, { small, self.fonts.tiny }) end
    self:panelButtonRow(x, y, pw, ph, { { 'close', game.started and 'BACK TO IT' or 'BEGIN', true } })
end

function UI:drawLevelFailed(game)
    local lv = game.level
    local x, y, pw, ph = self:panel(720, 260)
    self:centeredFit('LEVEL ' .. lv.index .. ' FAILED', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit(game.failReason or 'Somebody left the band.', y + 86, pw - 40, C.text, { self.fonts.hud, self.fonts.small })
    self:centeredFit('Nobody can be lost. Feed everyone to the end of the clock.', y + 120, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    self:panelButtonRow(x, y, pw, ph, { { 'retry', 'TRY AGAIN', true }, { 'title', 'TITLE', false } })
end

function UI:drawConfirmQuit()
    local x, y, pw, ph = self:panel(720, 230)
    self:centeredFit('Quit to the title screen?', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('Or start this one over.', y + 76, pw - 40, C.dim)
    self:panelButtonRow(x, y, pw, ph, { { 'restart', self.touch and 'RESTART' or 'RESTART (R)', false }, { 'yes', self.touch and 'QUIT' or 'QUIT (Y)', false, C.warn }, { 'no', 'KEEP PLAYING', true } })
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
    self:panelButtonRow(x, y, pw, ph, { { 'title', 'TITLE', true } })
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
    self:panelButtonRow(x, y, pw, ph, { { 'next', 'KEEP GOING', true }, { 'title', 'TITLE', false } })
end

return UI
