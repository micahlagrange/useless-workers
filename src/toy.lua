-- The Toybox look: one size system, cream plates with dark ink outlines,
-- one rounded face in three sizes, chunky buttons with a toy lip, and the
-- line-art icons the HUD draws them with. Everything here draws in the
-- HUD's virtual space (see UI:beginScaled); sizes are virtual pixels.
--
-- The spec is the Toybox radial mockup (epic-toybox-radial-ui):
-- https://claude.ai/artifact/Y5xfcFt91XHsBL1Ayg9X8y
local Toy = {}

-- Sizes -------------------------------------------------------------------
Toy.TAP = 56        -- every tap target
Toy.ICON = 28       -- every HUD icon
Toy.GAP = 8         -- gap between things
Toy.GUTTER = 16     -- screen edge to the HUD
Toy.R = 18          -- button corners
Toy.R_PLATE = 24    -- plate corners
Toy.LINE = 3        -- ink outline
Toy.LIP = 4         -- the toy lip under a button
Toy.S, Toy.M, Toy.L = 16, 20, 28 -- the only text sizes

-- Colours -----------------------------------------------------------------
local function hex(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 }
end
Toy.C = {
    ink = hex('3A2618'), inkSoft = hex('6B4F3D'),
    plate = hex('FFF6E3'), plate2 = hex('F5E4C3'),
    sun = hex('FFD45C'), leaf = hex('2E7D3E'), leaf2 = hex('CDEBB5'),
    berry = hex('B8304B'), amber = hex('8F5600'), white = { 1, 1, 1, 1 },
    meterGood = hex('4BA34B'), meterOk = hex('E0A000'), meterBad = hex('D9415E'),
}
local C = Toy.C

local function set(c, a) love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1)) end
Toy.set = set

-- Fonts -------------------------------------------------------------------
-- One rounded face (Fredoka, OFL), medium for body text and semibold for
-- names and buttons. Fonts are rasterised at the HUD's scale (LOVE's
-- dpiscale) so the text is crisp at any window size instead of being a
-- small font stretched; metrics stay in virtual pixels.
Toy.FONT_MEDIUM = 'assets/fonts/Fredoka-Medium.ttf'
Toy.FONT_SEMIBOLD = 'assets/fonts/Fredoka-SemiBold.ttf'
local cache = {}
local dpi = 1

function Toy.setScale(scale)
    -- the HUD's scale times the screen's own density (highdpi)
    local screen = (love.graphics.getDPIScale and love.graphics.getDPIScale()) or 1
    if type(screen) ~= 'number' or screen <= 0 then screen = 1 end
    local d = math.max(1, math.floor(scale * screen * 4 + 0.5) / 4)
    if d ~= dpi then dpi = d end
end

function Toy.font(size, bold)
    local key = size .. (bold and 'b' or 'm') .. '@' .. dpi
    local f = cache[key]
    if not f then
        f = love.graphics.newFont(bold and Toy.FONT_SEMIBOLD or Toy.FONT_MEDIUM, size, 'normal', dpi)
        f:setFilter('linear', 'linear')
        cache[key] = f
    end
    return f
end

-- Text --------------------------------------------------------------------
-- Text never shrinks to fit: it wraps at the same size.
function Toy.text(s, x, y, size, color, bold)
    local f = Toy.font(size, bold)
    love.graphics.setFont(f)
    set(color or C.ink)
    love.graphics.print(s, math.floor(x + 0.5), math.floor(y + 0.5))
    return f:getWidth(s), f:getHeight()
end

function Toy.width(s, size, bold) return Toy.font(size, bold):getWidth(s) end
function Toy.height(size, bold) return Toy.font(size, bold):getHeight() end

-- Lines of s wrapped to width at this size.
function Toy.wrap(s, width, size, bold)
    local _, lines = Toy.font(size, bold):getWrap(s, width)
    return lines
end

-- A wrapped paragraph. Returns its height.
function Toy.para(s, x, y, width, size, color, bold, lineGap)
    local f = Toy.font(size, bold)
    local lines = Toy.wrap(s, width, size, bold)
    local lh = f:getHeight() + (lineGap or 2)
    love.graphics.setFont(f)
    set(color or C.ink)
    for i, l in ipairs(lines) do love.graphics.print(l, math.floor(x + 0.5), math.floor(y + (i - 1) * lh + 0.5)) end
    return #lines * lh - (lineGap or 2)
end

-- Shapes ------------------------------------------------------------------
local function rrect(mode, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    love.graphics.rectangle(mode, x, y, w, h, r, r, 8)
end
Toy.rrect = rrect

-- A dashed rounded outline: dashes along the straight edges, the corners solid.
function Toy.dashedRect(x, y, w, h, r, dash, gap)
    dash, gap = dash or 6, gap or 4
    r = math.min(r, w / 2, h / 2)
    local function run(x1, y1, x2, y2)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local d = 0
        while d < len do
            local e = math.min(len, d + dash)
            love.graphics.line(x1 + (x2 - x1) * d / len, y1 + (y2 - y1) * d / len, x1 + (x2 - x1) * e / len, y1 + (y2 - y1) * e / len)
            d = e + gap
        end
    end
    run(x + r, y, x + w - r, y)
    run(x + w, y + r, x + w, y + h - r)
    run(x + w - r, y + h, x + r, y + h)
    run(x, y + h - r, x, y + r)
    love.graphics.arc('line', 'open', x + r, y + r, r, math.pi, math.pi * 1.5)
    love.graphics.arc('line', 'open', x + w - r, y + r, r, math.pi * 1.5, math.pi * 2)
    love.graphics.arc('line', 'open', x + w - r, y + h - r, r, 0, math.pi * 0.5)
    love.graphics.arc('line', 'open', x + r, y + h - r, r, math.pi * 0.5, math.pi)
end

-- A cream plate with an ink outline and a soft drop shadow.
function Toy.plate(x, y, w, h, r, fill, outline)
    r = r or Toy.R_PLATE
    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.28)
    rrect('fill', x, y + 5, w, h, r)
    set(fill or C.plate)
    rrect('fill', x, y, w, h, r)
    set(outline or C.ink)
    love.graphics.setLineWidth(Toy.LINE)
    rrect('line', x, y, w, h, r)
    love.graphics.setLineWidth(1)
end

-- A short label on a small plate, centred on cx; returns its rect.
function Toy.labelPlate(s, cx, y, size, extra, extraColor)
    size = size or Toy.S
    local w = Toy.width(s, size, true) + 16
    local ew = extra and (Toy.width(extra, size) + 6) or 0
    local h = Toy.height(size, true) + 4
    local x = math.floor(cx - (w + ew) / 2)
    set(C.plate)
    rrect('fill', x, y, w + ew, h, 12)
    set(C.ink)
    love.graphics.setLineWidth(Toy.LINE)
    rrect('line', x, y, w + ew, h, 12)
    love.graphics.setLineWidth(1)
    Toy.text(s, x + 8, y + 2, size, C.ink, true)
    if extra then Toy.text(extra, x + w - 2, y + 2, size, extraColor or C.inkSoft) end
    return { x = x, y = y, w = w + ew, h = h }
end

-- A Toybox button. o: { on, off (dashed, can't), round, fill, pressed,
-- badge = '1', badgeColor, icon = name, iconScale, bar = 0..100 }
function Toy.button(r, o)
    o = o or {}
    local rad = o.round and math.min(r.w, r.h) / 2 or Toy.R
    local dy = o.pressed and 3 or 0
    love.graphics.setLineWidth(Toy.LINE)
    if not o.off then
        set(C.ink)
        rrect('fill', r.x, r.y + (o.pressed and 1 or Toy.LIP), r.w, r.h, rad)
    end
    set(o.fill or (o.on and C.sun) or (o.off and C.plate2) or C.plate)
    rrect('fill', r.x, r.y + dy, r.w, r.h, rad)
    set(C.ink)
    if o.off then Toy.dashedRect(r.x, r.y, r.w, r.h, rad) else rrect('line', r.x, r.y + dy, r.w, r.h, rad) end
    if o.icon then
        local s = Toy.ICON * (o.iconScale or 1)
        local iy = r.y + dy + (r.h - s) / 2 - (o.bar and 6 or 0)
        Toy.icon(o.icon, r.x + (r.w - s) / 2, iy, s, o.off and 0.45 or 1)
    end
    if o.bar then
        local bx, by, bw, bh = r.x + 9, r.y + dy + r.h - 15, r.w - 18, 10
        set(C.plate2)
        rrect('fill', bx, by, bw, bh, 5)
        local v = math.max(0, math.min(100, o.bar))
        set(v > 60 and C.meterGood or v > 34 and C.meterOk or C.meterBad)
        if v > 0 then rrect('fill', bx, by, math.max(5, bw * v / 100), bh, 5) end
        set(C.ink)
        love.graphics.setLineWidth(2)
        rrect('line', bx, by, bw, bh, 5)
    end
    if o.badge then
        local bw = math.max(26, Toy.width(o.badge, Toy.S, true) + 12)
        local bx, by = r.x + r.w - bw + 8, r.y - 8
        set(o.badgeColor or C.ink)
        rrect('fill', bx, by, bw, 26, 13)
        set(C.ink)
        love.graphics.setLineWidth(2)
        rrect('line', bx, by, bw, 26, 13)
        Toy.text(o.badge, bx + (bw - Toy.width(o.badge, Toy.S, true)) / 2, by + (26 - Toy.height(Toy.S, true)) / 2, Toy.S, C.white, true)
    end
    love.graphics.setLineWidth(1)
end

function Toy.hit(r, x, y)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Icons -------------------------------------------------------------------
-- Drawn on a 32 x 32 grid, scaled to size. Ink outlines, flat fills.
local I = {}
Toy.ICONS = I

local function ink(w) set(C.ink) love.graphics.setLineWidth(w or 2.4) end
local function fill(h) set(hex(h)) end
local function poly(h, pts, lw)
    fill(h) love.graphics.polygon('fill', pts)
    ink(lw) love.graphics.polygon('line', pts)
end
local function circ(h, x, y, r, lw)
    fill(h) love.graphics.circle('fill', x, y, r)
    ink(lw) love.graphics.circle('line', x, y, r)
end
local function ell(h, x, y, rx, ry, lw)
    fill(h) love.graphics.ellipse('fill', x, y, rx, ry)
    ink(lw) love.graphics.ellipse('line', x, y, rx, ry)
end
local function box(h, x, y, w, hh, r, lw)
    fill(h) rrect('fill', x, y, w, hh, r or 0)
    ink(lw) rrect('line', x, y, w, hh, r or 0)
end
local function line(lw, ...) ink(lw) love.graphics.line(...) end

I.dig = function()
    poly('A9744A', { 22, 4, 28, 10, 25, 13, 19, 7 })
    poly('A9744A', { 19, 9, 23, 13, 14, 22, 10, 18 })
    poly('B9C3C9', { 10, 18, 14, 22, 11, 26, 4, 28, 6, 21 })
end
I.digger = I.dig
I.patch = function()
    set(hex('F2C6A8')) rrect('fill', 2, 2, 28, 28, 7)
    ink(2.2) Toy.dashedRect(2, 2, 28, 28, 7, 4, 3)
    love.graphics.push() love.graphics.translate(5, 5) love.graphics.scale(0.7) I.dig() love.graphics.pop()
end
I.unmark = function()
    I.dig()
    set(C.white) love.graphics.setLineWidth(7) love.graphics.line(5, 27, 27, 5)
    set(C.berry) love.graphics.setLineWidth(4) love.graphics.line(5, 27, 27, 5)
end
I.stash = function()
    ell('6DBE4B', 16, 19, 13, 8, 2.5)
    line(2, 5, 19, 27, 19) line(2, 10, 14, 14, 19) line(2, 16, 12, 16, 19) line(2, 22, 14, 18, 19)
end
I.basket = function()
    ink(2.5) love.graphics.arc('line', 'open', 16, 13, 7, math.pi, math.pi * 2)
    poly('D9A45B', { 4, 13, 28, 13, 25, 27, 7, 27 }, 2.5)
    line(1.8, 6, 18, 26, 18) line(1.8, 7, 23, 25, 23) line(1.8, 12, 13, 13, 27) line(1.8, 20, 13, 19, 27)
end
I.nest = function()
    fill('B07A47') love.graphics.ellipse('fill', 16, 17, 13, 7)
    ink(2.5) love.graphics.ellipse('line', 16, 17, 13, 7)
    line(1.8, 6, 17, 14, 21) line(1.8, 12, 15, 22, 21) line(1.8, 20, 15, 27, 19)
    ell('F2DFC0', 16, 13, 9, 3, 2)
end
I.bed = I.nest
I.bridge = function()
    for i = 0, 2 do box('C68B53', 3, 5 + i * 8, 26, 6, 2, 2.3) end
end
I.wall = function()
    box('B9A58C', 3, 6, 12, 8, 1.5, 2) box('B9A58C', 17, 6, 12, 8, 1.5, 2)
    box('B9A58C', 3, 16, 7, 8, 1.5, 2) box('B9A58C', 12, 16, 12, 8, 1.5, 2) box('B9A58C', 26, 16, 3, 8, 1, 2)
end
I.door = function()
    box('C68B53', 8, 4, 16, 25, 3, 2.4)
    circ('FFD45C', 20, 17, 1.8, 1.4)
end
I.trash = function()
    poly('F5E4C3', { 6, 9, 26, 9, 24, 28, 8, 28 })
    line(2.4, 4, 9, 28, 9) line(2.4, 12, 9, 12, 5, 20, 5, 20, 9) line(2.4, 13, 14, 13, 23) line(2.4, 19, 14, 19, 23)
end
I.pause = function() set(C.ink) rrect('fill', 8, 6, 6, 20, 2.5) rrect('fill', 18, 6, 6, 20, 2.5) end
I.play = function() set(C.ink) love.graphics.polygon('fill', 10, 6, 26, 16, 10, 26) end
I.menu = function() set(C.ink) for _, x in ipairs({ 7, 16, 25 }) do love.graphics.circle('fill', x, 16, 3.5) end end
I.close = function() line(4, 9, 9, 23, 23) line(4, 23, 9, 9, 23) end
I.back = function() line(4, 28, 16, 8, 16) line(4, 15, 8, 7, 16, 15, 24) end
I.next = function() line(4, 4, 16, 24, 16) line(4, 17, 8, 25, 16, 17, 24) end
I.more = function() line(4, 8, 12, 16, 20, 24, 12) end
I.speed1 = function() line(4, 11, 7, 20, 16, 11, 25) end
I.speed2 = function() line(4, 6, 7, 15, 16, 6, 25) line(4, 16, 7, 25, 16, 16, 25) end
I.speed4 = function()
    line(3.4, 2, 8, 9, 16, 2, 24) line(3.4, 10, 8, 17, 16, 10, 24) line(3.4, 18, 8, 25, 16, 18, 24) line(3.4, 29, 8, 29, 24)
end
I.bunch = function()
    poly('8FD3F0', { 3, 26, 4, 18, 7, 14, 11, 13, 15, 14, 18, 18, 19, 26 }, 2.3)
    poly('F59AC0', { 13, 26, 14, 16, 17, 11, 22, 10, 26, 11, 28, 16, 29, 26 }, 2.3)
    set(C.ink) love.graphics.circle('fill', 20, 17, 1.5) love.graphics.circle('fill', 25, 17, 1.5)
end
I.chat = function()
    poly('FFFFFF', { 4, 7, 7, 4, 25, 4, 28, 7, 28, 19, 25, 22, 13, 22, 7, 28, 7, 22, 4, 19 })
    set(C.ink) for _, x in ipairs({ 11, 16, 21 }) do love.graphics.circle('fill', x, 13, 2) end
end
I.stick = function()
    set(hex('8A5A33')) love.graphics.setLineWidth(5) love.graphics.line(5, 27, 27, 5) love.graphics.line(14, 18, 9, 11)
end
I.logs = I.stick
I.grass = function()
    poly('5DB043', { 6, 28, 2, 10, 10, 28 }, 2) poly('5DB043', { 14, 28, 16, 4, 18, 28 }, 2) poly('5DB043', { 22, 28, 30, 10, 26, 28 }, 2)
end
I.leaf = function()
    poly('7CC657', { 5, 27, 7, 16, 14, 8, 28, 4, 25, 16, 16, 24 }, 2.4)
    line(2, 6, 26, 22, 10)
end
I.leaves = I.leaf
I.shiny = function()
    poly('9EE3F5', { 16, 3, 27, 12, 16, 29, 5, 12 })
    line(1.6, 5, 12, 27, 12) line(1.6, 11, 12, 16, 29, 21, 12, 16, 3)
end
I.gold = I.shiny
I.food = function()
    circ('E2557A', 11, 19, 7, 2.3) circ('E2557A', 21, 20, 7, 2.3)
    line(2.3, 16, 12, 18, 7, 22, 4)
end
I.hungry = function()
    poly('F5E4C3', { 3, 15, 29, 15, 27, 21, 22, 26, 16, 27, 10, 26, 5, 21 })
    line(2, 12, 10, 13, 7, 14, 4) line(2, 18, 10, 19, 7, 20, 4)
end
I.grumble = function()
    poly('C9C3D6', { 6, 24, 2, 21, 5, 17, 6, 12, 14, 13, 18, 9, 24, 15, 29, 19, 24, 24 }, 2.3)
    line(2, 9, 29, 12, 25) line(2, 15, 29, 17, 25) line(2, 21, 29, 23, 25)
end
I.sun = function()
    for i = 0, 7 do
        local a = i * math.pi / 4
        line(2.4, 16 + math.cos(a) * 10, 16 + math.sin(a) * 10, 16 + math.cos(a) * 14, 16 + math.sin(a) * 14)
    end
    circ('FFD45C', 16, 16, 7, 2.4)
end
I.follow = function()
    poly('FFFFFF', { 2, 16, 9, 8, 16, 6, 23, 8, 30, 16, 23, 24, 16, 26, 9, 24 })
    set(C.ink) love.graphics.circle('fill', 16, 16, 5)
    set(C.white) love.graphics.circle('fill', 18, 14, 1.6)
end
I.home = function()
    poly('F2C27B', { 4, 16, 16, 5, 28, 16, 28, 28, 4, 28 })
    box('A9744A', 13, 20, 6, 8, 0, 2.4)
end
I.plus = function() box('B8E8A0', 4, 4, 24, 24, 6) line(3.4, 16, 9, 16, 23) line(3.4, 9, 16, 23, 16) end
I.check = function() line(4, 6, 17, 13, 24, 26, 9) end
I.restart = function()
    ink(3.4) love.graphics.arc('line', 'open', 16, 16, 10, -math.pi * 0.25, math.pi * 1.6)
    line(3.4, 17, 3, 24, 8, 18, 14)
end
I.export = function() line(2.6, 6, 14, 6, 27, 26, 27, 26, 14) line(2.8, 16, 20, 16, 4) line(2.8, 10, 10, 16, 4, 22, 10) end
I.history = function() circ('FFFFFF', 17, 16, 11) line(2.4, 17, 10, 17, 16, 21, 19) end
I.finger = function()
    poly('F2C27B', { 12, 28, 5, 18, 7, 16, 12, 20, 12, 6, 17, 6, 17, 14, 24, 15, 27, 19, 26, 25, 22, 28 }, 2.2)
end
I.egg = function()
    poly('7ED08A', { 16, 3, 22, 7, 27, 17, 25, 26, 16, 30, 7, 26, 5, 17, 10, 7 })
    set(C.ink) love.graphics.circle('fill', 12, 17, 1.8) love.graphics.circle('fill', 20, 17, 1.8)
end
I.sound = function()
    poly('FFE9A8', { 4, 12, 10, 12, 18, 6, 18, 26, 10, 20, 4, 20 })
    ink(2.4) love.graphics.arc('line', 'open', 18, 16, 6, -math.pi / 3, math.pi / 3)
    love.graphics.arc('line', 'open', 18, 16, 10, -math.pi / 3, math.pi / 3)
end
-- jobs
I.forager = function()
    circ('E2557A', 10, 19, 5, 2.2) circ('E2557A', 20, 22, 5, 2.2) circ('E2557A', 19, 12, 5, 2.2)
    line(2.2, 19, 7, 22, 4, 26, 3)
end
I.gatherer = function()
    set(hex('8A5A33')) love.graphics.setLineWidth(5) love.graphics.line(4, 22, 26, 8) love.graphics.line(6, 28, 28, 18)
    love.graphics.setLineWidth(4) love.graphics.line(16, 15, 13, 8)
    poly('7CC657', { 13, 8, 8, 9, 9, 12 }, 1.6)
end
I.lumberjack = I.gatherer
I.miner = I.dig
I.builder = function() box('A9744A', 12, 13, 5, 16, 2, 2.2) box('B9C3C9', 5, 5, 20, 9, 3, 2.4) end
I.caretaker = function()
    poly('F59AC0', { 16, 28, 6, 20, 3, 13, 4, 8, 8, 4, 12, 4, 16, 8, 20, 4, 24, 4, 28, 8, 29, 13, 26, 20 })
end
I.hunter = function()
    ell('F2C27B', 16, 21, 7, 6, 2.3)
    for _, p in ipairs({ { 7, 13 }, { 12.5, 7.5 }, { 19.5, 7.5 }, { 25, 13 } }) do circ('F2C27B', p[1], p[2], 3.5, 2.2) end
end
I.none = function() ink(3) love.graphics.circle('line', 16, 16, 11) love.graphics.line(8, 24, 24, 8) end
-- baby care
I.ball = function()
    circ('FFD45C', 16, 16, 12, 2.4)
    set(C.berry) love.graphics.setLineWidth(3) love.graphics.line(4, 16, 10, 13, 16, 12, 22, 13, 28, 16)
end
I.wash = function()
    circ('CDEFFF', 11, 19, 7, 2.3) circ('CDEFFF', 22, 12, 5, 2.3) circ('CDEFFF', 23, 24, 3.5, 2)
end
I.feed = function()
    poly('F5E4C3', { 3, 14, 29, 14, 27, 21, 22, 26, 16, 27, 10, 26, 5, 21 })
    circ('9B5FD1', 12, 12, 4, 1.8) circ('9B5FD1', 19, 11, 4, 1.8)
end
I.nap = function()
    fill('C9C3F0') love.graphics.circle('fill', 15, 17, 11)
    set(C.plate) love.graphics.circle('fill', 21, 12, 9)
    ink(2.4) love.graphics.arc('line', 'open', 15, 17, 11, -0.2, math.pi * 1.55)
end

function Toy.icon(name, x, y, size, alpha)
    local draw = I[name]
    if not draw then return end
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale((size or Toy.ICON) / 32)
    love.graphics.setLineJoin('bevel')
    if alpha and alpha < 1 then
        -- a faded icon for a button you can't use: draw it on a pale wash
        draw()
        love.graphics.setColor(C.plate2[1], C.plate2[2], C.plate2[3], 1 - alpha)
        love.graphics.rectangle('fill', 0, 0, 32, 32)
    else
        draw()
    end
    love.graphics.pop()
    love.graphics.setLineWidth(1)
end

return Toy
