-- Screen space: bars, buttons, alerts, the season's tally, title and end screens.
require('src.constants')
local Util = require('src.util')
local Scoring = require('src.scoring')
local Campaign = require('src.campaign')
local JobSets = require('src.jobsets')
local Version = require('src.version')
local Audio = require('src.audio')

local UI = {}
UI.__index = UI

TOP_BAR_H = 40
BOTTOM_BAR_H = 80
FONT_PATH = 'assets/fonts/commodore64.ttf'
local ALERT_TTL = 10

local C = {
    bar = { 0.08, 0.09, 0.07, 0.92 },
    panel = { 0.1, 0.11, 0.09, 0.96 },
    text = { 0.93, 0.93, 0.85 },
    dim = { 0.6, 0.62, 0.5 },
    accent = { 0.58, 0.64, 0.36 },
    warn = { 0.92, 0.45, 0.35 },
    good = { 0.55, 0.82, 0.55 },
    gold = { 1.0, 0.9, 0.45 },  -- the perfect clear, a cut above the stars' yellow
    amber = { 0.95, 0.72, 0.25 },
    blue = { 0.5, 0.75, 1.0 },
}

-- Hunger as a word and a colour.
local HUNGER_LOOK = {
    satiated = { 'SATIATED', 'blue' }, fed = { 'FED', 'good' }, hungry = { 'HUNGRY', 'amber' }, starving = { 'STARVING', 'warn' },
}
local function hungerLook(w)
    local h = HUNGER_LOOK[w:hungerStatus()]
    return h[1], C[h[2]]
end
UI.hungerLook = hungerLook

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
    }
    self.cursors = {
        select = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
        mine = love.graphics.newImage('assets/images/ui/plain_cursor.png'),
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
        { id = 'menu', label = 'MENU' }, { id = 'sound', label = 'SOUND' },
        { id = 'zoomin', label = '+' }, { id = 'zoomout', label = '-' },
        { id = 'follow', label = 'FOLLOW' }, { id = 'units', label = 'UNITS' }, { id = 'goal', label = 'GOAL' },
        { id = 'speed', label = 'SPEED 4x' }, { id = 'log', label = 'LOG' }, { id = 'tiles', label = 'TILES' },
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
function UI:star(cx, cy, r, filled, color)
    local pts = {}
    for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rad = (i % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = cx + math.cos(a) * rad
        pts[#pts + 1] = cy + math.sin(a) * rad
    end
    if filled and color then
        setColor(color)
        love.graphics.polygon('fill', pts)
        love.graphics.setColor(1, 1, 1, 0.9)
    elseif filled then
        love.graphics.setColor(0.95, 0.8, 0.25)
        love.graphics.polygon('fill', pts)
        love.graphics.setColor(0.6, 0.45, 0.1)
    else
        setColor(C.dim)
    end
    love.graphics.polygon('line', pts)
end



-- One alert at a time: a new one takes the old one's place (the log keeps
-- them all).
function UI:alert(text, tile)
    self.alerts = { { text = text, ttl = ALERT_TTL, tile = tile } }
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

-- The LOG button beside the alert.
function UI:alertLogAt(mx, my)
    return hit(self.alertLog, mx, my)
end

function UI:alertAt(mx, my)
    for _, r in ipairs(self.alertRects or {}) do
        if hit(r, mx, my) then return r.alert end
    end
    return nil
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
    return font:getHeight(), w
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

-- A tuft of grass.
function UI:iconGrass(x, y, s)
    love.graphics.setColor(0.42, 0.72, 0.34)
    love.graphics.setLineWidth(math.max(1, s * 0.08))
    for i = 0, 4 do
        local gx = x + s * (0.22 + i * 0.14)
        love.graphics.line(gx, y + s * 0.85, gx + s * (i - 2) * 0.06, y + s * (0.2 + (i % 2) * 0.15))
    end
    love.graphics.setLineWidth(1)
end

-- Two fallen leaves.
function UI:iconLeaves(x, y, s)
    love.graphics.setColor(0.92, 0.62, 0.3)
    love.graphics.ellipse('fill', x + s * 0.38, y + s * 0.55, s * 0.26, s * 0.15)
    love.graphics.setColor(0.8, 0.42, 0.24)
    love.graphics.ellipse('fill', x + s * 0.62, y + s * 0.42, s * 0.26, s * 0.15)
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
    -- a woven grass basket with two berries in it
    love.graphics.setColor(0.86, 0.72, 0.45)
    love.graphics.rectangle('fill', x + s * 0.1, y + s * 0.3, s * 0.8, s * 0.58, s * 0.12, s * 0.12)
    love.graphics.setColor(0.62, 0.46, 0.25)
    for i = 0, 3 do
        love.graphics.rectangle('fill', x + s * (0.18 + i * 0.18), y + s * 0.34, s * 0.05, s * 0.5)
    end
    love.graphics.setColor(0.72, 0.56, 0.32)
    love.graphics.setLineWidth(math.max(1, s * 0.06))
    love.graphics.arc('line', 'open', x + s * 0.5, y + s * 0.32, s * 0.3, math.pi, 2 * math.pi)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.foodIcon, x + s * 0.24, y + s * 0.16, 0, s * 0.24 / 16, s * 0.24 / 16)
    love.graphics.draw(self.foodIcon, x + s * 0.52, y + s * 0.16, 0, s * 0.24 / 16, s * 0.24 / 16)
end

-- A floor storage spot: a chalked square with a corner mark.
function UI:iconFloor(x, y, s)
    -- a stash: a big leaf laid flat with a berry on it
    love.graphics.setColor(0.55, 0.8, 0.45)
    love.graphics.ellipse('fill', x + s * 0.5, y + s * 0.55, s * 0.42, s * 0.3)
    love.graphics.setColor(0.4, 0.65, 0.33)
    love.graphics.line(x + s * 0.12, y + s * 0.62, x + s * 0.88, y + s * 0.48)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.foodIcon, x + s * 0.32, y + s * 0.3, 0, s * 0.36 / 16, s * 0.36 / 16)
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
    -- a nest: a ring of twigs with a soft middle (and an egg, for later)
    love.graphics.setColor(0.6, 0.45, 0.28)
    love.graphics.ellipse('fill', x + s * 0.5, y + s * 0.62, s * 0.44, s * 0.28)
    love.graphics.setColor(0.95, 0.88, 0.68)
    love.graphics.ellipse('fill', x + s * 0.5, y + s * 0.58, s * 0.28, s * 0.15)
    love.graphics.setColor(0.97, 0.95, 0.88)
    love.graphics.ellipse('fill', x + s * 0.5, y + s * 0.44, s * 0.12, s * 0.16)
    love.graphics.setColor(0.72, 0.55, 0.34)
    love.graphics.line(x + s * 0.1, y + s * 0.62, x + s * 0.32, y + s * 0.82)
    love.graphics.line(x + s * 0.68, y + s * 0.82, x + s * 0.9, y + s * 0.62)
end

-- DIG: a little round spade in a pile of dirt.
function UI:iconSpade(x, y, s)
    love.graphics.setColor(0.72, 0.55, 0.36)
    love.graphics.ellipse('fill', x + s * 0.5, y + s * 0.84, s * 0.4, s * 0.12)
    love.graphics.setColor(0.62, 0.45, 0.28)
    love.graphics.setLineWidth(math.max(1, s * 0.08))
    love.graphics.line(x + s * 0.68, y + s * 0.12, x + s * 0.48, y + s * 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.86, 0.82, 0.74)
    love.graphics.ellipse('fill', x + s * 0.42, y + s * 0.62, s * 0.16, s * 0.2)
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
    elseif kind == CARGO_GRASS then self:iconGrass(x, y, s)
    elseif kind == CARGO_LEAVES then self:iconLeaves(x, y, s)
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
        -- green at or under the clever target, plain to the easy one, red past it
        local spent, t = game.world.spent, game.level.def.targets
        pair('PTS', tostring(spent), spent <= t.clever and C.good or (spent <= t.easy and C.text or C.warn))
    elseif game.mode == 'level' then
        key = 1
    end
    icon(UI.iconLog, tostring(game.world.stock.logs), C.good)
    if not arcade then
        icon(UI.iconGrass, tostring(game.world.stock.grass or 0), C.good)
        icon(UI.iconLeaves, tostring(game.world.stock.leaves or 0), C.good)
    end
    local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
    icon(UI.iconFood, stored .. '/' .. cap, (cap == 0 and not arcade) and C.warn or C.text)
    icon(UI.iconMorphi, tostring(game.staffCount or 0))
    if not arcade then
        local hungry = 0
        for _, w in ipairs(game.workers) do
            if w.alive and (w:hungerStatus() == 'hungry' or w:hungerStatus() == 'starving') then hungry = hungry + 1 end
        end
        pair('HUNGRY', tostring(hungry), hungry > 0 and C.amber or C.good)
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
    -- DEV: the tester's tools (FINGERS, HISTORY, EXPORT), always on the bar
    local devW = self.fonts.small:getWidth('DEV') + self.quickPad
    local quickW = 0
    for _, d in ipairs(self.quickDefs) do quickW = quickW + d.w + 6 end
    local valuesBtnW = self.fonts.small:getWidth(key.word .. ' ' .. key.value) + 52
    local room = self.vw - 16 - 8 - pauseW - 6 - devW - 6
    local foldButtons = valuesW + 20 + quickW > room
    local foldValues = foldButtons and valuesW + 20 + gearW + 6 > room
    self.foldValues, self.foldButtons = foldValues, foldButtons
    -- buttons, right to left
    self.topButtons = {}
    local x = self.vw - 8 - pauseW
    self.topButtons[#self.topButtons + 1] = { id = 'pause', label = 'PAUSE', x = x, y = by, w = pauseW, h = bh }
    x = x - 6 - devW
    self.topButtons[#self.topButtons + 1] = { id = 'dev', label = 'DEV', x = x, y = by, w = devW, h = bh }
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
            local active = (b.id == 'follow' and game.follow) or (b.id == 'sound' and (game.muted or self.dropdown == 'sound')) or (b.id == 'pause' and game.paused)
                or (b.id == 'tiles' and game.tileset == 'rogue')
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
            local active = (d.id == 'follow' and game.follow) or (d.id == 'sound' and game.muted) or (d.id == 'speed' and (game.speed or 1) > 1)
                or (d.id == 'tiles' and game.tileset == 'rogue')
            local label = d.id == 'speed' and ('SPEED ' .. (game.speed or 1) .. 'x') or d.label
            self:button(r, label, active)
            self.dropButtons[#self.dropButtons + 1] = r
        end
    elseif self.dropdown == 'sound' then
        self:drawMixer(game)
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

local MIXER_ROWS = { { 'music', 'MUSIC' }, { 'sfx', 'EFFECTS' }, { 'alert', 'ALERTS' } }

-- The sound dropdown, under the SOUND button or the gear: mute, then a
-- volume bar for each channel with - and + either side.
function UI:drawMixer(game)
    local anchor
    for _, b in ipairs(self.topButtons) do
        if b.id == 'sound' or (b.id == 'gear' and not anchor) then anchor = b end
    end
    if not anchor then self.dropdown = nil return end
    local bh = self.quickH + 8
    local labelW = 0
    for _, row in ipairs(MIXER_ROWS) do labelW = math.max(labelW, self.fonts.small:getWidth(row[2])) end
    local pctW = self.fonts.small:getWidth('100%')
    local w = math.min(labelW + 12 + bh + 8 + 160 + 8 + bh + 8 + pctW, self.vw - 28)
    local x = math.max(14, math.min(anchor.x + anchor.w - w, self.vw - 14 - w))
    local y = TOP_BAR_H + 4
    local h = (#MIXER_ROWS + 1) * (bh + 6) + 6
    love.graphics.setColor(0.05, 0.05, 0.04, 0.94)
    love.graphics.rectangle('fill', x - 6, y - 2, w + 12, h + 4)
    local function add(r) self.dropButtons[#self.dropButtons + 1] = r end
    -- anything else in the panel is a press on nothing that keeps it open
    add({ id = 'values', x = x - 6, y = y - 2, w = w + 12, h = h + 4 })
    local function push(r) table.insert(self.dropButtons, #self.dropButtons, r) end
    local mute = { id = 'mute', x = x, y = y + 4, w = w, h = bh }
    self:button(mute, game.muted and 'MUTED - TAP FOR SOUND' or 'MUTE ALL (M)', game.muted)
    push(mute)
    for i, row in ipairs(MIXER_ROWS) do
        local channel, label = row[1], row[2]
        local ry = y + 4 + i * (bh + 6)
        local v = Audio.getVolume(channel)
        self:printLine(label, x, ry + math.floor((bh - self.fonts.small:getHeight()) / 2), labelW, 'left', game.muted and C.dim or C.text, { self.fonts.small })
        local bx = x + labelW + 12
        local minus = { id = 'vol:' .. channel .. ':-', x = bx, y = ry, w = bh, h = bh }
        local plus = { id = 'vol:' .. channel .. ':+', x = x + w - pctW - 8 - bh, y = ry, w = bh, h = bh }
        local bar = { id = 'volbar:' .. channel, x = minus.x + bh + 8, y = ry, w = plus.x - 8 - (minus.x + bh + 8), h = bh }
        self:button(minus, '-')
        self:button(plus, '+')
        love.graphics.setColor(0.16, 0.17, 0.14, 1)
        love.graphics.rectangle('fill', bar.x, bar.y + bh / 2 - 5, bar.w, 10)
        setColor(game.muted and C.dim or C.accent)
        love.graphics.rectangle('fill', bar.x, bar.y + bh / 2 - 5, math.floor(bar.w * v + 0.5), 10)
        self:printLine(math.floor(v * 100 + 0.5) .. '%', plus.x + bh + 4, ry + math.floor((bh - self.fonts.small:getHeight()) / 2), pctW + 4, 'right', C.text, { self.fonts.small })
        push(minus) push(plus) push(bar)
    end
end

-- What a press hits in the open dropdown: a button id, 'inside', or nil,
-- and the button's rectangle.
function UI:dropdownAt(mx, my)
    for _, b in ipairs(self.dropButtons or {}) do
        if hit(b, mx, my) then return b.id == 'values' and 'inside' or b.id, b end
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
    local why = 'Out of sticks and nobody can reach food.'
    local f = self.fonts.small:getWidth(why) <= self.vw - 16 and self.fonts.small or self.fonts.tiny
    self:printLine(why, 8, r.y + r.h + 6, self.vw - 16, 'right', C.warn, { f })
    self.restartButton = r
    self.restartBottom = r.y + r.h + 6 + f:getHeight()
end

function UI:restartButtonAt(mx, my)
    return hit(self.restartButton, mx, my)
end

-- While following a morphi: previous and next, at the corners just above
-- the bottom bar.
function UI:drawFollowNav(game)
    self.followNav = {}
    -- shown whenever there is a morphi to go to, following or not
    local any = false
    for _, w in ipairs(game.workers or {}) do
        if w.alive and w.state ~= 'quitting' then any = true break end
    end
    if not any then return end
    local prev = self.touch and '<' or '< ['
    local nxt = self.touch and '>' or '] >'
    local bw = math.max(self.touch and 64 or 0, self.fonts.hud:getWidth(prev) + 28)
    local bh = self.quickH + 8
    local y = self.vh - BOTTOM_BAR_H - bh - 8
    -- above the one-line strip a narrow screen shows for the picked morphi
    local w = game.selectedWorker
    if not self.portrait and self.panelW == 0 and w and w.alive then y = y - 26 end
    -- a short screen whose floating arcade goals reach down this far: they win
    local goals = self:goalBoxRect(game)
    if goals and goals.y + goals.h > y - 4 then return end
    -- at the edges, clear of the toast in the middle
    local r1 = { id = -1, x = 8, y = y, w = bw, h = bh }
    local r2 = { id = 1, x = self.vw - 8 - bw, y = y, w = bw, h = bh }
    self:button(r1, prev)
    self:button(r2, nxt)
    self.followNav = { r1, r2 }
end

-- -1 or 1 for the previous or next button, else nil.
function UI:followNavAt(mx, my)
    for _, r in ipairs(self.followNav or {}) do
        if hit(r, mx, my) then return r.id end
    end
    return nil
end

function UI:drawAlerts(game)
    love.graphics.setFont(self.fonts.small)
    local y = (self.bannerBottom or TOP_BAR_H) + 8
    local box = game and self:goalBoxRect(game)
    -- room on the right for the LOG button that opens the announcements
    local logW = self.fonts.small:getWidth('LOG') + 28
    local maxW = (box and box.x - 16 or self.vw) - 40 - logW - 8
    local bottom = self.vh - BOTTOM_BAR_H - 70 -- the toast lives below this
    self.alertRects = {}
    self.alertLog = nil
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        -- a tap looks at the place; the hint says so
        local text = a.text .. (a.tile and '  > look' or '')
        local _, lines = self.fonts.small:getWrap(text, maxW)
        local h = #lines * self.fonts.small:getHeight() + 8
        if y + h > bottom then break end
        local w = math.min(self.fonts.small:getWidth(text), maxW) + 12
        love.graphics.setColor(0, 0, 0, 0.65 * alpha)
        love.graphics.rectangle('fill', 12, y, w, h)
        if a.tile then
            love.graphics.setColor(C.warn[1], C.warn[2], C.warn[3], 0.6 * alpha)
            love.graphics.rectangle('line', 12.5, y + 0.5, w - 1, h - 1)
        end
        love.graphics.setColor(C.warn[1], C.warn[2], C.warn[3], alpha)
        love.graphics.setFont(self.fonts.small)
        love.graphics.printf(text, 18, y + 4, maxW, 'left')
        self.alertRects[#self.alertRects + 1] = { x = 12, y = y, w = w, h = h, alert = a }
        local r = { x = 12 + w + 8, y = y, w = logW, h = math.max(h, self.quickH) }
        self:button(r, 'LOG', false)
        self.alertLog = r
        y = y + math.max(h, r.h) + 4
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
    if tool == ABILITY_MINE then self:iconSpade(x, y, size)
    elseif tool == ABILITY_STORAGE then self:iconFloor(x, y, size)
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
    self.jobsButton = nil
    self.followButton = nil
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
        if w and w.alive and w.jobSet then
            -- free play: name (JOBS opens the job screen), its three jobs,
            -- what it is doing, how it is
            local lh = self.fonts.small:getHeight() + 6
            local jw, fw = 72, 96
            local _, nw = self:printLine(w.name .. ', the ' .. w.species, ix, iy, iw - jw - fw - 8 - 32, 'left', C.good, { self.fonts.hud, self.fonts.small })
            self:iconFoodKind(w.diet, ix + nw + 6, iy - 1, 18)
            self:followButtonDraw(game, { x = ix + iw - jw - 8 - fw, y = iy - 4, w = fw, h = 28 })
            self:jobsButtonDraw({ x = ix + iw - jw, y = iy - 4, w = jw, h = 28 })
            self:printLine(self:jobsSummary(w), ix, iy + lh + 6, iw, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            self:printLine(w:describeState(), ix, iy + 2 * lh + 6, iw, 'left', C.text, { self.fonts.small, self.fonts.tiny })
            local word, color = hungerLook(w)
            self:printLine(word .. ', ' .. w:mood(), ix, iy + 3 * lh + 6, iw, 'left', color, { self.fonts.small, self.fonts.tiny })
        elseif w and w.alive then
            local lh = self.fonts.small:getHeight() + 8
            local fw = 96
            self:followButtonDraw(game, { x = ix + iw - fw, y = iy - 4, w = fw, h = 28 })
            -- the name line, with what it eats at the end, as on the units list
            local _, nw = self:printLine(w.name .. ', the ' .. w.species .. ', ' .. w.roleInfo.label:lower(), ix, iy, iw - fw - 32, 'left', C.good, { self.fonts.hud, self.fonts.small })
            self:iconFoodKind(w.diet, ix + nw + 6, iy - 1, 18)
            self:printLine(w:describeState(), ix, iy + lh + 4, iw, 'left', C.text, { self.fonts.small, self.fonts.tiny })
            if w:isBaby() then
                self:printLine(w:babySummary(), ix, iy + 2 * lh + 4, iw, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            elseif w.arcade then
                self:printLine(w.ate and 'has eaten' or 'not eaten yet', ix, iy + 2 * lh + 4, iw, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            else
                local word, color = hungerLook(w)
                self:printLine(word .. ', ' .. w:mood(), ix, iy + 2 * lh + 4, iw, 'left', color, { self.fonts.small, self.fonts.tiny })
            end
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
            -- FOLLOW (and JOBS in free play) at the top right, what it eats before them
            local jw = w.jobSet and 56 or 0
            local fw = 76
            local bx0 = px + pw - jw - (jw > 0 and 6 or 0) - fw
            self:followButtonDraw(game, { x = bx0, y = py - 4, w = fw, h = 22 })
            if w.jobSet then self:jobsButtonDraw({ x = px + pw - jw, y = py - 4, w = jw, h = 22 }) end
            local words = w.jobSet and ('the ' .. w.species .. ', eats') or ('the ' .. w.species .. ', ' .. w.roleInfo.label:lower() .. ', eats')
            self:printLine(words, nx, py + 3, bx0 - 26 - 6 - nx, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            self:iconFoodKind(w.diet, bx0 - 24, py - 2, 18)
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
            local under = w:isBaby() and w:babySummary() or w.jobSet and self:jobsSummary(w, true) or ('hauled ' .. w.delivered .. '  grumbles ' .. w.complaintCount)
            self:printLine(under, sx + 6, py + 46, pw - 150 - 66, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
            local bx = px + pw - 140
            setColor(C.dim)
            love.graphics.setFont(self.fonts.tiny)
            if w.arcade then
                love.graphics.print('MEAL', bx, py + 22)
                self:printLine(w.ate and 'eaten' or 'not yet', bx, py + 36, 140, 'left', w.ate and C.good or C.warn, { self.fonts.small, self.fonts.tiny })
                self:printLine('JOB ' .. w.roleInfo.label:lower(), bx, py + 52, 140, 'left', C.dim, { self.fonts.tiny })
            else
                love.graphics.print('HUNGER', bx, py + 22)
                local word, color = hungerLook(w)
                self:printLine(word, bx, py + 34, 140, 'left', color, { self.fonts.small, self.fonts.tiny })
                setColor(C.dim)
                love.graphics.print('MOOD ' .. w:mood(), bx, py + 50)
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
        local line = w.name .. ': ' .. w:describeState() .. (w.arcade and (w.ate and '  (eaten)' or '') or ('  ' .. hungerLook(w):lower() .. ', ' .. w:mood()))
        local ty = self.vh - BOTTOM_BAR_H - 22
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', 8, ty, self.vw - 16, 20)
        local room = self.vw - 28 - 76
        local fx = self.vw - 8 - 70
        if w.jobSet then
            room = room - 70
            self:jobsButtonDraw({ x = self.vw - 8 - 64, y = ty, w = 64, h = 20 })
            fx = fx - 70
        end
        self:followButtonDraw(game, { x = fx, y = ty, w = 70, h = 20 })
        self:printLine(line, 14, ty + 4, room, 'left', C.text, { self.fonts.small, self.fonts.tiny })
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
        -- above the < > buttons when they show
        local nav = self.followNav and self.followNav[1]
        if nav then ty = math.min(ty, nav.y - th - 6) end
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle('fill', tx, ty, tw, th)
        self:printLine(self.toastText, tx + 10, ty + 6, tw - 20, 'left', C.warn, { f })
        love.graphics.setFont(self.fonts.hud)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The FOLLOW button on the picked morphi's strip: lit while following.
function UI:followButtonDraw(game, r)
    self:button(r, 'FOLLOW', game.follow == true)
    self.followButton = r
end

function UI:followButtonAt(mx, my)
    return hit(self.followButton, mx, my)
end

-- The JOBS button on the picked morphi's strip (free play only).
function UI:jobsButtonDraw(r)
    self:button(r, 'JOBS', false)
    self.jobsButton = r
end

function UI:jobsButtonAt(mx, my)
    return hit(self.jobsButton, mx, my)
end

function UI:insideJobPanel(mx, my)
    return hit(self.jobPanel, mx, my)
end

-- A morphi's three jobs in a line: 'forager, then miner, dislikes builder'.
-- short is for the tight desk strip.
function UI:jobsSummary(w, short)
    local js = w.jobSet
    if not js then return w.roleInfo.label:lower() end
    if short then
        return JobSets.label(js.main) .. ' / ' .. (js.neutral and JobSets.label(js.neutral) or 'no fallback') .. ' / not ' .. JobSets.label(js.disliked)
    end
    -- 'lumberjack, then builder, dislikes miner': main, neutral, disliked
    local neutral = js.neutral and ('then ' .. JobSets.label(js.neutral)) or 'no fallback'
    return JobSets.label(js.main) .. ', ' .. neutral .. ', dislikes ' .. JobSets.label(js.disliked)
end

-- The job screen for the picked morphi: tap a MAIN job and a NEUTRAL job
-- (or NONE); the DISLIKED job is shown and cannot be changed. A choice that
-- is not allowed is drawn in the warning colour and says why when tapped.
-- Buttons are panel buttons with ids 'job:<slot>:<job or none>'.
function UI:drawJobs(game)
    local w = game.selectedWorker
    if not (w and w.alive and w.jobSet) then return end
    local js = w.jobSet
    -- a short screen (a phone on its side) packs the rows a little tighter
    local short = self.vh < 420
    local gap = short and 6 or 8
    local bh = (self.touch and not short) and 38 or 30
    local small = self.fonts.small
    -- < and > for the previous and next morphi sit at the panel's sides
    -- (the screen's sides on a phone); the choices go between them
    local navW = math.max(36, small:getWidth('<') + 20)
    local side = 10 + navW + 8
    local pw = math.min(760 + 2 * (side - 18), self.vw - 16)
    local inner = pw - 2 * side
    local minW = small:getWidth('LUMBERJACK') + 12
    local cols = Util.clamp(math.floor((inner + gap) / (minW + gap)), 1, 5)
    local bw = math.floor((inner - (cols - 1) * gap) / cols)
    local function rowsFor(n) return math.ceil(n / cols) end
    -- the explanations wrap in the small face (a phone held upright has no
    -- room for them on one line, and the tiny face is hard to read)
    local hints = {
        main = 'MAIN JOB: done first, whenever there is any',
        neutral = 'NEUTRAL JOB: done when the main job has nothing',
    }
    hints.disliked = js.main == js.disliked and 'DISLIKED JOB: it is the main job now'
        or 'DISLIKED JOB: done only when nothing else is left'
    local trait = 'Part of who ' .. w.name .. ' is. It never changes.'
    local function wrapH(text, width)
        local _, lines = small:getWrap(text, width or inner)
        return #lines * small:getHeight()
    end
    local stateH = small:getHeight() + 6
    -- the header: UNITS (back to the list) and CLOSE on the right; the
    -- title beside them when it fits, else on a row of its own below
    local btnW = 100
    local unitsW = small:getWidth('UNITS') + 24
    local buttonsW = unitsW + btnW + 8
    local title = w.name .. "'s jobs"
    local titleRow = small:getWidth(title) > pw - 36 - buttonsW - 10
    local top = titleRow and 52 + self.fonts.hud:getHeight() + 6 or 52
    local ph = top + stateH + 6
        + wrapH(hints.main) + 6 + rowsFor(#JobSets.JOBS) * (bh + gap) + 6
        + wrapH(hints.neutral) + 6 + rowsFor(#JobSets.JOBS + 1) * (bh + gap) + 6
        + wrapH(hints.disliked) + 6 + math.max(bh, wrapH(trait, inner - bw - 12)) + 12
    local x, y
    x, y, pw, ph = self:panel(pw, ph)
    self.jobPanel = { x = x, y = y, w = pw, h = ph }
    local unitsX = x + pw - btnW - 18 - 8 - unitsW
    if titleRow then
        self:printLine(title, x + 18, y + 52, pw - 36, 'left', C.good, { self.fonts.hud, self.fonts.small })
    else
        self:printLine(title, x + 18, y + 16, unitsX - x - 18 - 10, 'left', C.good, { self.fonts.big, self.fonts.hud, self.fonts.small })
    end
    self:panelButton('units', { x = unitsX, y = y + 12, w = unitsW, h = 30 }, 'UNITS', false)
    -- the previous and next morphi, at the screen's sides, level with the panel's middle
    local navH = 72
    local navY = y + top + math.floor((ph - top - navH) / 2)
    self:panelButton('jobprev', { x = x + 10, y = navY, w = navW, h = navH }, '<', false)
    self:panelButton('jobnext', { x = x + pw - 10 - navW, y = navY, w = navW, h = navH }, '>', false)
    self:panelButton('close', { x = x + pw - btnW - 18, y = y + 12, w = btnW, h = 30 }, 'CLOSE', false)
    local cy = y + top
    local lx = x + side
    self:printLine(w:describeState(), lx, cy, inner, 'left', C.text, { self.fonts.small, self.fonts.tiny })
    cy = cy + stateH + 6
    -- one block of choices; choices[i] = false stands for NONE. The job in
    -- the slot is lit; the others are dimmed so it stands out, a choice that
    -- is not allowed dimmer still in red, the disliked job (allowed as main)
    -- in a dim amber.
    local DIM_WARN, DIM_AMBER = { 0.55, 0.33, 0.28 }, { 0.68, 0.53, 0.25 }
    local function grid(slot, choices)
        cy = cy + self:printWrap(hints[slot], lx, cy, inner, C.text, { small }, 3) + 6
        for i, choice in ipairs(choices) do
            local job = choice or nil
            local r, c = math.floor((i - 1) / cols), (i - 1) % cols
            local rect = { x = lx + c * (bw + gap), y = cy + r * (bh + gap), w = bw, h = bh }
            local current = js[slot] == job
            local ok = current or JobSets.canSet(js, slot, job)
            local label = job and JobSets.label(job):upper() or 'NONE'
            local color = nil
            if not current then
                color = (not ok) and DIM_WARN or (job and job == js.disliked and DIM_AMBER) or C.dim
            end
            self:panelButton('job:' .. slot .. ':' .. (job or 'none'), rect, label, current, color)
        end
        cy = cy + rowsFor(#choices) * (bh + gap) + 6
    end
    grid('main', JobSets.JOBS)
    local neutral = { false }
    for _, job in ipairs(JobSets.JOBS) do neutral[#neutral + 1] = job end
    grid('neutral', neutral)
    -- the disliked job in a box like the others, so it reads the same;
    -- tapping it only says why it cannot change
    cy = cy + self:printWrap(hints.disliked, lx, cy, inner, C.text, { small }, 3) + 6
    self:panelButton('job:disliked:' .. js.disliked, { x = lx, y = cy, w = bw, h = bh }, JobSets.label(js.disliked):upper(), false, C.warn)
    -- why it cannot change, beside the box (a short screen has no row to spare)
    local tw = inner - bw - 12
    local th = wrapH(trait, tw)
    self:printWrap(trait, lx + bw + 12, cy + math.max(0, math.floor((bh - th) / 2)), tw, C.dim, { small }, 4)
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
    self:drawFollowNav(game)
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
    -- free play rows also have JOBS beside FOLLOW
    local anyJobs = false
    for _, w in ipairs(units) do if w.jobSet then anyJobs = true end end
    local jobsW = anyJobs and (compact and 64 or 72) or 0
    self:printLine('UNITS  (' .. #units .. ' morphis)', x + 18, y + 16, pw - btnW - 52, 'left', C.text, { self.fonts.big, self.fonts.hud, self.fonts.small })
    local cName = x + 18 + rowH
    local right = x + pw - btnW - 24 - (jobsW > 0 and jobsW + 8 or 0)
    local cTask = compact and x + math.floor(pw * 0.42) or x + math.floor(pw * 0.34)
    -- the hunger and morale columns share out what the buttons leave
    local cHunger, cMorale = x + math.floor((right - x) * 0.72), x + math.floor((right - x) * 0.88)
    -- a phone with JOBS and FOLLOW on each row: the task goes under the
    -- name instead of in a column of its own
    local stacked = compact and jobsW > 0
    if stacked then cTask = right end
    local wide = pw >= 760
    local arcade = game.mode == 'arcade'
    self:printLine('MORPHI', cName, y + 56, cTask - cName - 8, 'left', C.dim, { self.fonts.tiny })
    if not stacked then self:printLine('TASK', cTask, y + 56, (compact and right or cHunger) - cTask - 8, 'left', C.dim, { self.fonts.tiny }) end
    if not compact then
        self:printLine(arcade and 'MEAL' or 'HUNGER', cHunger, y + 56, (wide and not arcade and cMorale or right) - cHunger - 8, 'left', C.dim, { self.fonts.tiny })
        if wide and not arcade then self:printLine('MOOD', cMorale, y + 56, right - cMorale - 8, 'left', C.dim, { self.fonts.tiny }) end
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
        if stacked and rowH < 44 then
            -- one line: name and what it is doing
            self:printLine(w.name .. ': ' .. w:describeState(), cName, ry + 8, cTask - cName - 8, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        else
            self:printLine(w.name, cName, ry + 4, nameW, 'left', C.good, nameFonts)
            local nf = love.graphics.getFont()
            self:iconFoodKind(w.diet, cName + math.min(nf:getWidth(w.name), nameW) + 6, ry + 2, 16)
        end
        if rowH >= 44 then
            local second = stacked and w:describeState() or (w.species .. ', ' .. w.roleInfo.label:lower())
            self:printLine(second, cName, ry + 26, cTask - cName - 8, 'left', stacked and C.text or C.dim, { self.fonts.small, self.fonts.tiny })
        end
        local taskRight = compact and right or cHunger
        if not stacked then
            self:printLine(w:describeState(), cTask, ry + 8, taskRight - cTask - 10, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        end
        if not compact then
            local barW = (wide and not arcade and cMorale or right) - cHunger - 12
            if arcade then
                self:printLine(w.ate and 'eaten' or 'not yet', cHunger, ry + 8, barW, 'left', w.ate and C.good or C.warn, { self.fonts.small, self.fonts.tiny })
            else
                local word, color = hungerLook(w)
                self:printLine(word, cHunger, ry + 8, barW, 'left', color, { self.fonts.small, self.fonts.tiny })
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
        self.unitButtons[#self.unitButtons + 1] = { worker = w, what = 'follow', x = r.x, y = r.y, w = r.w, h = r.h }
        if w.jobSet then
            local jr = { x = r.x - jobsW - 8, y = r.y, w = jobsW, h = 28 }
            self:button(jr, 'JOBS', false)
            self.unitButtons[#self.unitButtons + 1] = { worker = w, what = 'jobs', x = jr.x, y = jr.y, w = jr.w, h = jr.h }
        end
        ry = ry + rowH
    end
    self:panelButton('close', { x = x + pw - btnW - 18, y = y + 12, w = btnW, h = 30 }, 'CLOSE', false)
    love.graphics.setColor(1, 1, 1, 1)
end

-- The log: what happened, newest first, with what kind of thing it was and
-- a LOOK button for anything that happened somewhere. At the top, this
-- season's hardships by kind.
local LOG_KIND = {
    hardship = { 'GRUMBLE', 'warn' }, warning = { 'GRUMPY', 'warn' }, left = { 'LEFT', 'warn' }, news = { 'NEWS', 'dim' },
}
function UI:drawLog(game)
    local log = game.log or {}
    local pw = math.min(900, self.vw - 24)
    local ph = self.vh - TOP_BAR_H - 24
    local x, y
    x, y, pw, ph = self:panel(pw, ph)
    y = math.max(y, TOP_BAR_H + 8)
    self.logPanel = { x = x, y = y, w = pw, h = ph }
    local btnW = self.touch and 100 or 110
    self:printLine('LOG', x + 18, y + 14, pw - btnW - 52, 'left', C.text, { self.fonts.big, self.fonts.hud })
    self:panelButton('close', { x = x + pw - btnW - 18, y = y + 12, w = btnW, h = 30 }, 'CLOSE', false)
    -- this season, by kind
    local season = game.scoring and game.scoring:seasonLabel() or ''
    local counts, order = {}, {}
    for _, e in ipairs(log) do
        if e.season == season and e.kind ~= 'news' then
            local key = e.kind == 'hardship' and (e.text:find('is hungry and') and 'hungry, food out of reach'
                or e.text:find('nothing to do') and 'nothing to do' or 'could not reach')
                or (e.kind == 'left' and 'left' or 'very grumpy')
            if not counts[key] then order[#order + 1] = key end
            counts[key] = (counts[key] or 0) + 1
        end
    end
    if game.mode == 'arcade' then season = '' end -- arcade has no seasons
    local summary = (season ~= '' and season or 'So far') .. ': '
    if #order == 0 then summary = summary .. 'no grumbles yet'
    else
        local parts = {}
        for _, k in ipairs(order) do parts[#parts + 1] = counts[k] .. ' ' .. k end
        summary = summary .. table.concat(parts, ', ')
    end
    local ly = y + 54
    ly = ly + self:printWrap(summary, x + 18, ly, pw - 36, C.text, { self.fonts.small, self.fonts.tiny }, 2) + 10
    love.graphics.setColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
    love.graphics.rectangle('fill', x + 18, ly, pw - 36, 1)
    ly = ly + 8
    if #log == 0 then
        self:printLine('Nothing has happened yet.', x + 18, ly, pw - 36, 'left', C.dim, { self.fonts.small, self.fonts.tiny })
        return
    end
    local small, tiny = self.fonts.small, self.fonts.tiny
    local lookW = self.touch and 78 or 70
    local kindW = tiny:getWidth('GRUMBLE') + 10
    for i = #log, 1, -1 do
        local e = log[i]
        local textX = x + 18 + kindW
        local textW = pw - 36 - kindW - (e.tile and lookW + 10 or 0)
        local _, lines = tiny:getWrap(e.text, textW)
        local rowH = math.max(self.touch and 34 or 28, #lines * tiny:getHeight() + tiny:getHeight() + 10)
        if ly + rowH > y + ph - 10 then break end
        local k = LOG_KIND[e.kind] or LOG_KIND.news
        self:printLine(k[1], x + 18, ly + 3, kindW - 6, 'left', C[k[2]], { tiny })
        self:printLine(e.season, x + 18, ly + 3 + tiny:getHeight(), kindW - 6, 'left', C.dim, { tiny })
        self:printWrap(e.text, textX, ly + 3, textW, C.text, { tiny }, 99)
        if e.tile then
            self:panelButton('look:' .. i, { x = x + pw - 18 - lookW, y = ly + 2, w = lookW, h = math.min(rowH - 6, 28) }, 'LOOK', false)
        end
        ly = ly + rowH
    end
end

function UI:insideLogPanel(mx, my)
    return hit(self.logPanel, mx, my)
end

-- The morphi whose row button is under the pointer, and which button:
-- 'follow' or 'jobs'.
function UI:unitButtonAt(mx, my)
    for _, b in ipairs(self.unitButtons) do
        if hit(b, mx, my) then return b.worker, b.what end
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
        { 'Sticks', tostring(report.logs), UI.iconLog },
        { 'Shinies', tostring(report.gold), UI.iconGold },
        { 'Fed', report.fedPct .. '%' },
        { 'Grumbles', tostring(report.complaints), UI.iconComplaint },
        { 'Wandered off', tostring(report.attrition) },
        { 'New eggs', '+' .. (report.eggs or report.hires or 0), UI.iconMorphi },
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
        y = y + self:centeredFit('A bunch of little blobs in a big meadow.', y, self.vw - 24, C.dim, { self.fonts.hud, self.fonts.small }) + 2
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
            local best, aim = '', ''
            if opt.best then
                local stars = Campaign.stars(opt.best, opt.def)
                best = '   best ' .. opt.best .. (opt.best == 0 and opt.set == 'arcade' and ' (PERFECT)' or ' (' .. stars .. ' star' .. (stars == 1 and '' or 's') .. ')')
            end
            if opt.def.targets then aim = ', aim for ' .. opt.def.targets.easy .. ', clever ' .. opt.def.targets.clever
            else aim = ', par ' .. opt.def.par end
            local _, h = self:centered(points .. ' points to spend' .. aim .. best, y, self.fonts.small, C.text)
            y = y + h + 4 + gap(16)
            if opt.set == 'arcade' then
                local ad = ARCADE_DIFFICULTIES[title.arcadeDifficulty]
                diffRow(ad.name:upper())
                y = y + self:centeredFit(ad.blurb, y, self.vw - 24, C.dim, { self.fonts.small, self.fonts.tiny })
            end
            y = y + gap(20)
        end
    else
        if FREE_PLAY_DIFFICULTIES > 1 then diffRow(diff.name:upper())
        else
            local _, dh = self:centered(diff.name:upper(), y, self.fonts.hud, C.text)
            y = y + dh + 8
        end
        y = y + self:centeredFit(diff.workers .. ' little blobs, hunger ' .. diff.drain .. '/s, score x' .. diff.multiplier .. ', seasons and newcomers', y, self.vw - 24, C.dim, { self.fonts.small, self.fonts.tiny }) + gap(30)
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
        'ARCADE: every morphi wants one meal. Give the bunch what it insists on, spend as few points as you can.',
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
    -- which build this is, for telling a stale page from a new one
    love.graphics.setFont(self.fonts.tiny)
    setColor(C.dim)
    love.graphics.print('build ' .. Version.build, 8, 10)
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

-- The buttons under a finished run: the run's history and its export.
local RUN_BUTTONS = { { 'history', 'HISTORY', false }, { 'export', 'EXPORT', false } }

function UI:drawLevelClear(game)
    local lv = game.level
    local last = lv.index >= #game.levels
    local x, y, pw, ph = self:panel(720, last and 350 or 320)
    self:centeredFit(Campaign.title[lv.set] .. ' ' .. lv.index .. ' CLEAR: ' .. lv.def.name:upper(), y + 28, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    -- a perfect clear (not a single log) earns a fourth star, in gold
    local n = lv.perfect and 4 or 3
    for i = 1, n do
        local cx = x + pw / 2 + (i - (n + 1) / 2) * 64
        if i == 4 then self:star(cx, y + 100, 28, true, C.gold) else self:star(cx, y + 100, 24, i <= lv.stars) end
    end
    local spent = game.world.spent
    local logs = spent .. ' log' .. (spent == 1 and '' or 's')
    if lv.def.targets then
        local t = lv.def.targets
        self:centeredFit('spent ' .. logs .. ' (aim ' .. t.easy .. ', clever ' .. t.clever .. ')', y + 150, pw - 40, C.text, { self.fonts.hud, self.fonts.small })
        local line, color, fonts = '', C.dim, { self.fonts.small, self.fonts.tiny }
        if lv.perfect then line, color, fonts = 'PERFECT. Not a single log.', C.gold, { self.fonts.hud, self.fonts.small }
        elseif spent <= t.clever then line, color, fonts = 'Clever. Three stars.', C.good, { self.fonts.hud, self.fonts.small }
        elseif spent <= t.easy then line = 'Two stars. A sharper eye spends ' .. t.clever .. '.'
        else line = 'One star. Try for ' .. t.easy .. ' or fewer: the narrow crossing, the thin stone, the nook.' end
        self:centeredFit(line, y + 180, pw - 40, color, fonts)
    else
        local par = lv.def.par
        self:centeredFit('spent ' .. logs .. ', par ' .. par, y + 150, pw - 40, C.text, { self.fonts.hud })
        self:centeredFit(spent <= par and 'At or under par.' or 'A sharper eye spends ' .. par .. '.', y + 180, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    end
    if lv.isNewBest then self:centered('NEW BEST', y + 215, self.fonts.hud, C.good) end
    if not last then
        self:panelButtonRow(x, y, pw, ph, { { 'next', 'NEXT LEVEL', true }, { 'title', 'TITLE', false }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
    else
        self:centeredFit('All ' .. #game.levels .. ' levels clear.', y + 250, pw - 40, C.text, { self.fonts.hud })
        self:panelButtonRow(x, y, pw, ph, { { 'title', 'TITLE', true }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
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
            { def.points .. ' points to spend, par ' .. def.par .. '. Bridges, baskets and nests cost points. Digging is free. Sticks are points.', C.dim },
        }
    else
        title = 'FREE PLAY'
        lines = {
            { 'A random meadow, four seasons, newcomers when the haul is good. Grumbles and hunger wear their mood down; at zero a morphi leaves.', C.text },
            { 'Bushes wear out and new ones pop up out of reach. A morphi with nothing it can get at gets bored: DIG through the clay (shinies hide in it) and BRIDGE to open the way, and lay a STASH or a BASKET for the berries.', C.text },
            { 'Each morphi loves one food (a big meal and a better mood) and hates one. Shinies from the diggers buy happy thoughts at the home nest.', C.dim },
        }
    end
    local eaters, seen = {}, {}
    for _, w in ipairs(game.workers) do
        if w.alive and not seen[w.sheet] then
            seen[w.sheet] = true
            local label = w.hates and (w.species .. ' loves ' .. w.diet .. ', hates ' .. w.hates) or (w.species .. ' eats ' .. w.diet)
            eaters[#eaters + 1] = { label = label, diet = w.diet }
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
    -- a short screen loses the last lines of text, then the list of tastes
    -- (the units list has them too)
    while height(body) > self.vh - 16 and #lines > 1 do table.remove(lines) end
    if height(body) > self.vh - 16 then eaters = {} end
    local x, y, ph
    x, y, pw, ph = self:panel(pw, height(body))
    self:centeredFit(title, y + 22, pw - 40, C.good, { self.fonts.big, self.fonts.hud })
    local ly = y + 64
    for _, line in ipairs(lines) do
        ly = ly + self:printWrap(line[1], x + 24, ly, inner, line[2], { body }, 99) + 10
    end
    -- who eats what
    ly = ly + 6
    if #eaters > 0 then
        self:printLine(game.mode == 'free' and 'TASTES' or 'WHO EATS WHAT', x + 24, ly, inner, 'left', C.dim, { small, self.fonts.tiny })
    end
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
    local t = def.targets
    local costs = points .. ' points to spend on ' .. diff.name:lower() .. '. Spend ' .. t.easy .. ' or fewer for two stars, ' .. t.clever .. ' or fewer for three, none at all for a PERFECT. Bins, walls, doors and bridge tiles cost a log each; floors and mining are free.'
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
    self:centeredFit(game.failReason or 'Somebody wandered off.', y + 86, pw - 40, C.text, { self.fonts.hud, self.fonts.small })
    self:centeredFit('Nobody can be lost. Feed everyone to the end of the clock.', y + 120, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    self:panelButtonRow(x, y, pw, ph, { { 'retry', 'TRY AGAIN', true }, { 'title', 'TITLE', false }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
end

function UI:drawConfirmQuit()
    local x, y, pw, ph = self:panel(720, 230)
    self:centeredFit('Quit to the title screen?', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('Or start this one over.', y + 76, pw - 40, C.dim)
    self:panelButtonRow(x, y, pw, ph, { { 'restart', self.touch and 'RESTART' or 'RESTART (R)', false }, { 'yes', self.touch and 'QUIT' or 'QUIT (Y)', false, C.warn }, { 'no', 'KEEP PLAYING', true } })
end

-- The milestones the run reached, under the score: one line each, as many
-- as fit between top and bottom. Returns the y after them.
function UI:drawMilestones(stats, x, y, w, bottom)
    local list = stats and stats.milestones or {}
    if #list == 0 then return y end
    local tiny = self.fonts.tiny
    local lh = tiny:getHeight() + 4
    self:printLine('MILESTONES', x, y, w, 'center', C.accent, { self.fonts.small, tiny })
    y = y + self.fonts.small:getHeight() + 6
    local first = math.max(1, #list - math.floor((bottom - y) / lh) + 1)
    for i = first, #list do
        local m = list[i]
        self:printLine(m.season .. ': ' .. m.text, x, y, w, 'center', C.text, { self.fonts.small, tiny })
        y = y + lh
    end
    return y
end

function UI:drawGameOver(scoring, highScore, isNew, stats)
    local x, y, pw, ph = self:panel(720, 360 + (stats and #stats.milestones > 0 and 40 + 22 * math.min(#stats.milestones, 4) or 0))
    self:centeredFit('Everyone wandered off.', y + 30, pw - 40, C.warn, { self.fonts.big, self.fonts.hud })
    self:centeredFit('Nobody was left by ' .. Scoring.seasonName(scoring.quarter):lower(), y + 80, pw - 40, C.dim)
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), y + math.floor(ph * 0.42), pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', y + math.floor(ph * 0.58), self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, y + math.floor(ph * 0.58), self.fonts.hud, C.dim)
    end
    self:drawMilestones(stats, x + 20, y + math.floor(ph * 0.58) + 40, pw - 40, y + ph - 70)
    self:panelButtonRow(x, y, pw, ph, { { 'title', 'TITLE', true }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
end

function UI:drawAnnual(scoring, highScore, isNew, stats)
    local x, y, pw, ph = self:panel(720, 420 + (stats and #stats.milestones > 0 and 40 + 22 * #stats.milestones or 0))
    self:centered('THE YEAR IS OVER', y + 24, self.fonts.big, C.good)
    love.graphics.setFont(self.fonts.hud)
    local rs = math.min(26, math.floor((ph - 200) / math.max(#scoring.reports, 1)))
    local ry = y + 70
    for _, r in ipairs(scoring.reports) do
        setColor(C.dim)
        love.graphics.setFont(self.fonts.hud)
        love.graphics.print(Scoring.seasonName(r.quarter):sub(1, 3):upper(), x + 30, ry)
        self:printFit('haul ' .. r.output .. '  food ' .. r.food .. '  sticks ' .. r.logs .. '  shinies ' .. r.gold .. '  grumbles ' .. r.complaints .. '  lost ' .. r.attrition .. '  grade ' .. r.grade,
            x + 90, ry + 2, pw - 110, 'left', C.text, { self.fonts.small, self.fonts.tiny })
        ry = ry + rs
    end
    self:centeredFit('FINAL SCORE: ' .. scoring:finalScore(), ry + 20, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    if isNew then
        self:centered('NEW HIGH SCORE', ry + 66, self.fonts.hud, C.good)
    else
        self:centered('HIGH SCORE: ' .. highScore, ry + 66, self.fonts.hud, C.dim)
    end
    self:drawMilestones(stats, x + 20, ry + 106, pw - 40, y + ph - 70)
    self:panelButtonRow(x, y, pw, ph, { { 'next', 'KEEP GOING', true }, { 'title', 'TITLE', false }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
end

-- The tester's corner: FINGERS, and the run's audit log.
function UI:drawTools(fingerDebug)
    local x, y, pw, ph = self:panel(620, 300)
    self:centeredFit('TESTER TOOLS', y + 24, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    self:centeredFit('For finding bugs and tuning the meadow.', y + 76, pw - 40, C.dim, { self.fonts.small, self.fonts.tiny })
    local bw, bh = math.min(260, pw - 40), self.touch and 44 or 36
    local bx = x + math.floor((pw - bw) / 2)
    self:panelButton('fingers', { x = bx, y = y + 110, w = bw, h = bh }, fingerDebug and 'FINGERS: ON' or 'FINGERS: OFF', fingerDebug)
    self:panelButtonRow(x, y, pw, ph, { { 'back', 'BACK', true }, RUN_BUTTONS[1], RUN_BUTTONS[2] })
end

-- EXPORT: a few words from the player, then the run is written out.
-- saved, once the note is in: {json, name, days, web, message}. On the web
-- the page shows the text in a box of its own over the game; here, the
-- start of it, with COPY and DOWNLOAD.
function UI:drawExport(text, saved)
    local x, y, pw, ph = self:panel(760, saved and not saved.web and 460 or 380)
    self:centeredFit('EXPORT THIS RUN', y + 20, pw - 40, C.text, { self.fonts.big, self.fonts.hud })
    if saved then
        local tiny = self.fonts.tiny
        local head = saved.days .. ' days as ' .. saved.name
        self:printWrap(head, x + 24, y + 70, pw - 48, C.dim, { self.fonts.small, tiny }, 2)
        if saved.web and not saved.message then
            self:printWrap('The run is in the text box over the game. Copy it, or download it, then paste it into the run viewer.', x + 24, y + 120, pw - 48, C.good, { self.fonts.small, tiny }, 4)
            self:panelButtonRow(x, y, pw, ph, { { 'done', 'DONE', true } })
            return
        end
        -- the preview gives up room for the message under it
        local msgH = 0
        if saved.message then
            local _, ml = tiny:getWrap(saved.message, pw - 48)
            msgH = #ml * tiny:getHeight() + 8
        end
        local box = { x = x + 24, y = y + 116, w = pw - 48, h = math.max(tiny:getHeight() + 12, ph - 200 - msgH) }
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle('fill', box.x, box.y, box.w, box.h)
        local _, lines = tiny:getWrap(saved.json:sub(1, 4000), box.w - 16)
        local fit = math.max(1, math.floor((box.h - 12) / tiny:getHeight()))
        setColor(C.text)
        love.graphics.setFont(tiny)
        for i = 1, math.min(fit, #lines) do
            love.graphics.print(lines[i], box.x + 8, box.y + 6 + (i - 1) * tiny:getHeight())
        end
        if saved.message then
            self:printWrap(saved.message, x + 24, box.y + box.h + 8, pw - 48, C.good, { tiny }, 99)
        end
        self:panelButtonRow(x, y, pw, ph, saved.web and { { 'done', 'DONE', true } }
            or { { 'copy', 'COPY', true }, { 'download', 'DOWNLOAD', false }, { 'done', 'DONE', false } })
        return
    end
    self:printWrap('What was fun? What was not? (' .. STATS_BLURB_MAX .. ' letters at most)', x + 24, y + 70, pw - 48, C.dim, { self.fonts.small, self.fonts.tiny }, 2)
    local box = { x = x + 24, y = y + 120, w = pw - 48, h = ph - 210 }
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle('fill', box.x, box.y, box.w, box.h)
    setColor(C.accent)
    love.graphics.rectangle('line', box.x + 0.5, box.y + 0.5, box.w - 1, box.h - 1)
    self.panelButtons[#self.panelButtons + 1] = { id = 'typing', x = box.x, y = box.y, w = box.w, h = box.h }
    local caret = math.floor(love.timer.getTime() * 2) % 2 == 0 and '_' or ' '
    self:printWrap(text .. caret, box.x + 10, box.y + 8, box.w - 20, C.text, { self.fonts.small, self.fonts.tiny }, 5)
    self:printLine(#text .. '/' .. STATS_BLURB_MAX, box.x, box.y + box.h + 4, box.w, 'right', C.dim, { self.fonts.tiny })
    self:panelButtonRow(x, y, pw, ph, { { 'cancel', 'CANCEL', false }, { 'save', self.touch and 'SAVE' or 'SAVE (ENTER)', true } })
end

-- HISTORY: the run as a plain list, newest at the bottom, scrolled by
-- whole lines with the arrows.
function UI:drawHistory(lines, scroll)
    local x, y, pw, ph = self:panel(900, self.vh - 24)
    self:printLine('HISTORY', x + 18, y + 14, pw - 36, 'left', C.text, { self.fonts.big, self.fonts.hud })
    local tiny = self.fonts.tiny
    local lh = tiny:getHeight() + 6
    local top, bottom = y + 60, y + ph - 70
    local fit = math.max(1, math.floor((bottom - top) / lh))
    if #lines == 0 then
        self:printLine('Nothing worth writing down yet.', x + 18, top, pw - 36, 'left', C.dim, { self.fonts.small, tiny })
    end
    local first = math.max(1, math.min(#lines - fit + 1, #lines - fit + 1 - (scroll or 0)))
    for i = first, math.min(#lines, first + fit - 1) do
        self:printLine(lines[i], x + 18, top + (i - first) * lh, pw - 36, 'left', C.text, { tiny })
    end
    local defs = { { 'close', 'CLOSE', true } }
    if #lines > fit then
        table.insert(defs, 1, { 'older', 'OLDER', false })
        defs[#defs + 1] = { 'newer', 'NEWER', false }
    end
    self:panelButtonRow(x, y, pw, ph, defs)
    return fit
end

return UI
