-- The Toybox HUD over the meadow (epic-toybox-radial-ui, tb-topbar, tb-time):
-- the stock plate and the five buttons, alert pills, the toast, the pause
-- plate, the arcade goals, and the menu sheet. Adds methods to UI; ui.lua
-- calls this at its end. Draws in the HUD's virtual space.
local Toy = require('src.toy')
local Util = require('src.util')
local Audio = require('src.audio')
local Campaign = require('src.campaign')

return function(UI)
local C = Toy.C
local TAP, GAP, GUT = Toy.TAP, Toy.GAP, Toy.GUTTER

local function hit(r, x, y)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Layout ---------------------------------------------------------------------

UI.TOY_BUTTONS = { 'pause', 'speed', 'bunch', 'menu' }

function UI:layoutToy()
    self.toyPhone = self.vw < 720
    local n = #UI.TOY_BUTTONS
    local clusterW = n * TAP + (n - 1) * GAP
    local by = self.toyPhone and (GUT + TAP + 12) or GUT
    self.toyCluster = {}
    for i, id in ipairs(UI.TOY_BUTTONS) do
        self.toyCluster[i] = { id = id, x = self.vw - GUT - clusterW + (i - 1) * (TAP + GAP), y = by, w = TAP, h = TAP }
    end
    self.toyPlateMax = self.toyPhone and (self.vw - 2 * GUT) or (self.vw - 2 * GUT - clusterW - 12)
    TOP_BAR_H = by + TAP + 12
    self.toyTopBottom = TOP_BAR_H - 12
end

-- The stock plate's items, most important first. wide ones may hide behind
-- the expand button.
function UI:toyStock(game)
    local sc = game.scoring
    local arcade = game.mode == 'arcade'
    local out = {}
    local function add(t) out[#out + 1] = t end
    local time = Util.formatTime(arcade and game.clock or sc.quarterTimer)
    local label = sc:seasonLabel()
    if game.mode == 'level' or arcade then label = 'Level ' .. game.level.index end
    local blink = not arcade and sc.quarterTimer <= 15 and math.floor(sc.quarterTimer * 2) % 2 == 0
    add({ key = 'season', icon = 'sun', text = label .. ' ' .. time, warn = blink, season = true })
    if arcade then
        local ate, pop = Campaign.ateCount(game.workers), #game.level.def.morphis
        add({ key = 'ate', icon = 'food', text = 'ate ' .. ate .. '/' .. pop, good = ate >= pop })
        local spent, t = game.world.spent, game.level.def.targets
        add({ key = 'pts', icon = 'shiny', text = spent .. ' spent', warn = spent > t.easy, good = spent <= t.clever })
    else
        local stored, cap = game.world:storedCount(ITEM_FOOD), game.world:storageCapacity()
        add({ key = 'food', icon = 'food', text = stored .. '/' .. cap, warn = cap == 0 })
    end
    add({ key = 'sticks', icon = 'stick', text = tostring(game.world.stock.logs), warn = game.world.stock.logs == 0 })
    if not arcade then
        add({ key = 'shinies', icon = 'shiny', text = tostring(game.world.stock.gold) })
        local hungry = 0
        for _, w in ipairs(game.workers) do
            if w.alive and (w:hungerStatus() == 'hungry' or w:hungerStatus() == 'starving') then hungry = hungry + 1 end
        end
        add({ key = 'hungry', icon = 'hungry', text = tostring(hungry), warn = hungry > 0, button = true })
        add({ key = 'grass', icon = 'grass', text = tostring(game.world.stock.grass or 0), wide = true })
        add({ key = 'leaves', icon = 'leaf', text = tostring(game.world.stock.leaves or 0), wide = true })
        add({ key = 'grumbles', icon = 'grumble', text = tostring(sc.complaints), warn = sc.complaints > 0, wide = true })
    end
    add({ key = 'bunch', icon = 'bunch', text = tostring(game.staffCount or 0), wide = true })
    for _, it in ipairs(out) do it.w = 8 + Toy.ICON + 6 + Toy.width(it.text, Toy.M, true) + 8 end
    return out
end

-- Top bar --------------------------------------------------------------------

function UI:drawToyTop(game, menuOpen)
    self.topButtons = {}
    local items = self:toyStock(game)
    local max = self.toyPlateMax
    local pad, gap = 6, 2
    local tight = self.toyPhone
    -- a phone packs the cells closer and the clock loses its season word
    local function cellW(it)
        local inner = (tight and 4 or 8)
        return inner + Toy.ICON + (tight and 4 or 6) + Toy.width(it.text, Toy.M, true) + inner
    end
    if tight then
        for _, it in ipairs(items) do
            if it.season then it.text = it.text:match('(%d+:%d+)$') or it.text end
        end
    end
    for _, it in ipairs(items) do it.w = cellW(it) end
    local function rowWidth(list, more)
        local w = 2 * pad + (more and (36 + gap) or 0)
        for i, it in ipairs(list) do w = w + it.w + (i > 1 and gap or 0) end
        return w
    end
    -- what fits on one row: the wide ones go behind the expand button first,
    -- then the least important of the rest, from the end
    local shown, rest = {}, {}
    for _, it in ipairs(items) do shown[#shown + 1] = it end
    if rowWidth(shown) > max then
        local keep = {}
        for _, it in ipairs(shown) do if it.wide then rest[#rest + 1] = it else keep[#keep + 1] = it end end
        shown = keep
        while #shown > 1 and rowWidth(shown, true) > max do
            table.insert(rest, 1, table.remove(shown))
        end
    end
    local hidden = #rest > 0
    local rows = { shown }
    if hidden and self.resOpen then
        -- the rest on rows of their own, as many as they need
        local row = {}
        for _, it in ipairs(rest) do
            if #row > 0 and rowWidth(row) + gap + it.w > max then rows[#rows + 1] = row row = {} end
            row[#row + 1] = it
        end
        rows[#rows + 1] = row
    end
    local plateW = 0
    for i, r in ipairs(rows) do plateW = math.max(plateW, rowWidth(r, i == 1 and hidden)) end
    if tight then plateW = max end
    local rowH = 44
    local plateH = TAP + (#rows - 1) * (rowH + 2)
    local px, py = GUT, GUT
    Toy.plate(px, py, plateW, plateH)
    self.toyPlateRect = { x = px, y = py, w = plateW, h = plateH }
    for ri, r in ipairs(rows) do
        local x = px + pad
        local y = py + (TAP - 40) / 2 + (ri - 1) * (rowH + 2)
        if tight and ri == 1 then
            -- spread over the full width plate
            local extra = (plateW - rowWidth(r, hidden)) / math.max(1, #r)
            for _, it in ipairs(r) do it.w = it.w + extra end
        end
        for _, it in ipairs(r) do
            local cell = { x = x, y = y, w = it.w, h = 40 }
            if it.season then
                Toy.set(C.plate2)
                Toy.rrect('fill', cell.x, cell.y, cell.w, cell.h, 12)
            elseif it.button and it.warn then
                love.graphics.setColor(0.976, 0.867, 0.886, 1)
                Toy.rrect('fill', cell.x, cell.y, cell.w, cell.h, 12)
            end
            local cw = Toy.ICON + (tight and 4 or 6) + Toy.width(it.text, Toy.M, true)
            local cx = cell.x + (cell.w - cw) / 2
            local since = love.timer.getTime() - ((self.bumps or {})[it.key] or -10)
            local grow = since < 0.5 and (1 + 0.35 * math.sin(since / 0.5 * math.pi)) or 1
            local is = Toy.ICON * grow
            Toy.icon(it.icon, cx - (is - Toy.ICON) / 2, cell.y + 6 - (is - Toy.ICON) / 2, is)
            Toy.text(it.text, cx + Toy.ICON + (tight and 4 or 6), cell.y + (40 - Toy.height(Toy.M, true)) / 2, Toy.M, it.warn and C.berry or (it.good and C.leaf) or C.ink, true)
            if it.button then self.topButtons[#self.topButtons + 1] = { id = it.key, x = cell.x, y = cell.y, w = cell.w, h = cell.h } end
            x = x + it.w + gap
        end
        if ri == 1 and hidden then
            local r2 = { id = 'resmore', x = px + plateW - pad - 36, y = py + (TAP - 40) / 2 + 2, w = 36, h = 36 }
            Toy.button(r2, {})
            love.graphics.push()
            love.graphics.translate(r2.x + 4, r2.y + 4)
            love.graphics.scale(28 / 32)
            if self.resOpen then love.graphics.translate(32, 32) love.graphics.rotate(math.pi) end
            Toy.ICONS.more()
            love.graphics.pop()
            love.graphics.setLineWidth(1)
            self.topButtons[#self.topButtons + 1] = r2
        end
    end
    -- the buttons: on a phone they sit under the plate, however tall it is
    if self.toyPhone then
        for _, b in ipairs(self.toyCluster) do b.y = py + plateH + 12 end
    end
    for _, b in ipairs(self.toyCluster) do
        local o = {}
        if b.id == 'pause' then o.icon, o.on = game.paused and 'play' or 'pause', game.paused
        elseif b.id == 'speed' then
            local s = game.speed or 1
            o.icon, o.on, o.badge = 'speed' .. (s >= 4 and 4 or s >= 2 and 2 or 1), s > 1, s .. 'x'
        elseif b.id == 'bunch' then o.icon = 'bunch'
        elseif b.id == 'menu' then o.icon, o.on = 'menu', menuOpen end
        Toy.button(b, o)
        self.topButtons[#self.topButtons + 1] = b
    end
    self.toyTopBottom = math.max(py + plateH, self.toyCluster[1].y + TAP)
    self.toyStackY = self.toyTopBottom + 20
    -- the plates under the bar keep to the room left of the arcade goals
    local goals = not self.toyPhone and self:goalBoxRectToy(game)
    self.toyStackL, self.toyStackR = GUT, goals and (goals.x - 12) or (self.vw - GUT)
end

-- Under the bar ---------------------------------------------------------------

-- Paused: a plate under the bar. The world is stopped; the ring still works.
function UI:drawToyPause(game)
    if not game.paused then return end
    local line = 'The bunch is having a little rest. You can still mark and set things out.'
    local btnW = Toy.width('Carry on', Toy.M, true) + 16 + Toy.ICON + 12 + 16
    local room = self.toyStackR - self.toyStackL
    local w = math.min(room, 640)
    local textW = w - 16 - btnW - 24
    local lh = #Toy.wrap(line, textW, Toy.S) * (Toy.height(Toy.S) + 2)
    local h = math.max(TAP + 16, Toy.height(Toy.M, true) + lh + 20)
    local x, y = math.floor(self.toyStackL + (room - w) / 2), self.toyStackY
    Toy.plate(x, y, w, h)
    Toy.text('Paused', x + 16, y + 10, Toy.M, C.ink, true)
    Toy.para(line, x + 16, y + 12 + Toy.height(Toy.M, true), textW, Toy.S, C.inkSoft)
    local b = { id = 'carryon', x = x + w - 8 - btnW, y = y + (h - TAP) / 2, w = btnW, h = TAP }
    self:toyRow(b, 'Carry on', 'play', true)
    self.topButtons[#self.topButtons + 1] = b
    self.toyStackY = y + h + 12
end

-- When an arcade level is stuck: start it over.
function UI:drawToyRestart(game)
    self.restartButton = nil
    if not game.suggestRestart then return end
    local why = 'Out of sticks and nobody can reach food.'
    local label = 'Start this level over'
    local btnW = Toy.width(label, Toy.M, true) + 32 + Toy.ICON + 12
    local w = math.min(self.toyStackR - self.toyStackL, math.max(btnW, Toy.width(why, Toy.S)) + 32)
    local lh = #Toy.wrap(why, w - 32, Toy.S) * (Toy.height(Toy.S) + 2)
    local h = 12 + lh + 8 + TAP + 12
    local x, y = self.toyStackR - w, self.toyStackY
    Toy.plate(x, y, w, h, nil, nil, C.berry)
    Toy.para(why, x + 16, y + 12, w - 32, Toy.S, C.berry)
    local b = { x = x + 16, y = y + 12 + lh + 8, w = w - 32, h = TAP }
    self:toyRow(b, label, 'restart', true)
    self.restartButton = b
    self.toyStackY = y + h + 12
end

-- A row button: icon, label, 56 tall.
function UI:toyRow(r, label, icon, warm)
    Toy.button(r, { on = warm })
    local x = r.x + 16
    if icon then
        Toy.icon(icon, x, r.y + (r.h - Toy.ICON) / 2, Toy.ICON)
        x = x + Toy.ICON + 12
    end
    Toy.text(label, x, r.y + (r.h - Toy.height(Toy.M, true)) / 2, Toy.M, C.ink, true)
end

-- Arcade goals: a plate at the top right, under the buttons.
function UI:goalBoxRectToy(game)
    if game.mode ~= 'arcade' then return nil end
    local goals = Campaign.goals(game.level, game.workers)
    local w = math.min(340, self.vw - 2 * GUT)
    local rowH = 28
    local inner = w - 32 - 30
    local h = 12 + Toy.height(Toy.S, true) + 6
    for _, g in ipairs(goals) do h = h + math.max(rowH, #Toy.wrap(g.label, inner, Toy.S) * (Toy.height(Toy.S) + 2)) + 4 end
    h = h + 8
    return { x = self.vw - GUT - w, y = self.toyTopBottom + 20, w = w, h = h, goals = goals, inner = inner }
end

function UI:drawToyGoals(game)
    local r = self:goalBoxRectToy(game)
    if not r then return end
    if self.toyPhone then r.y = self.toyStackY end
    Toy.plate(r.x, r.y, r.w, r.h)
    Toy.text('Before anyone eats', r.x + 16, r.y + 10, Toy.S, C.inkSoft, true)
    local y = r.y + 12 + Toy.height(Toy.S, true) + 6
    for _, g in ipairs(r.goals) do
        local bx, by = r.x + 16, y + 2
        Toy.set(g.done and C.leaf2 or C.plate2)
        Toy.rrect('fill', bx, by, 22, 22, 6)
        Toy.set(C.ink)
        love.graphics.setLineWidth(2)
        Toy.rrect('line', bx, by, 22, 22, 6)
        if g.done then
            love.graphics.setLineWidth(3)
            love.graphics.line(bx + 5, by + 12, bx + 9, by + 16, bx + 17, by + 6)
        end
        love.graphics.setLineWidth(1)
        local h = Toy.para(g.label, bx + 30, y + 2, r.inner, Toy.S, g.done and C.leaf or C.ink)
        y = y + math.max(28, h) + 4
    end
    if self.toyPhone then self.toyStackY = r.y + r.h + 12 end
end

-- Alert pills: one announcement at a time; a tap goes to the place.
function UI:drawToyAlerts(game)
    self.alertRects = {}
    self.alertLog = nil
    local x, y = self.toyStackL, self.toyStackY
    local maxW = math.min(560, self.toyStackR - x)
    for _, a in ipairs(self.alerts) do
        local alpha = math.min(1, a.ttl / 1.5)
        local look = a.tile and 'Look' or nil
        local lookW = look and (Toy.width(look, Toy.S, true) + 8 + 24) or 0
        local textW = maxW - 24 - lookW
        local lines = Toy.wrap(a.text, textW, Toy.M, true)
        local lh = Toy.height(Toy.M, true) + 2
        local w = math.min(maxW, Toy.width(a.text, Toy.M, true) + 24 + lookW)
        local h = math.max(TAP, #lines * lh + 14)
        love.graphics.push('all')
        love.graphics.setColor(1, 1, 1, alpha)
        Toy.set(C.berry, alpha)
        Toy.rrect('fill', x, y + Toy.LIP, w, h, Toy.R)
        Toy.set(C.plate, alpha)
        Toy.rrect('fill', x, y, w, h, Toy.R)
        Toy.set(C.berry, alpha)
        love.graphics.setLineWidth(Toy.LINE)
        Toy.rrect('line', x, y, w, h, Toy.R)
        local f = Toy.font(Toy.M, true)
        love.graphics.setFont(f)
        for i, l in ipairs(lines) do love.graphics.print(l, math.floor(x + 12), math.floor(y + (h - #lines * lh) / 2 + (i - 1) * lh)) end
        if look then
            Toy.text(look, x + w - lookW + 2, y + (h - Toy.height(Toy.S, true)) / 2, Toy.S, C.ink, true)
            Toy.icon('next', x + w - 30, y + (h - 22) / 2, 22)
        end
        love.graphics.pop()
        self.alertRects[#self.alertRects + 1] = { x = x, y = y, w = w, h = h, alert = a }
        y = y + h + 12
    end
    self.toyAlertBottom = y
end

-- The toast: a plate in the middle, under whatever sits under the bar.
function UI:drawToyToast()
    if not self.toastText then return end
    local room = self.toyStackR - self.toyStackL
    local maxW = math.min(560, room)
    local iw = self.toastIcon and (Toy.ICON + 10) or 0
    local lines = Toy.wrap(self.toastText, maxW - 32 - iw, Toy.M, true)
    local lh = Toy.height(Toy.M, true) + 2
    local w = math.min(maxW, Toy.width(self.toastText, Toy.M, true) + 32 + iw)
    local h = #lines * lh + 18
    local y = math.max(self.toyStackY, self.toyAlertBottom or 0)
    local x = math.floor(self.toyStackL + (room - w) / 2)
    Toy.plate(x, y, w, h)
    local f = Toy.font(Toy.M, true)
    love.graphics.setFont(f)
    Toy.set(C.ink)
    if self.toastIcon then Toy.icon(self.toastIcon, x + 14, y + (h - Toy.ICON) / 2, Toy.ICON) end
    love.graphics.setFont(f)
    Toy.set(C.ink)
    for i, l in ipairs(lines) do
        love.graphics.print(l, math.floor(x + iw + (w - iw - f:getWidth(l)) / 2), math.floor(y + 9 + (i - 1) * lh))
    end
end

function UI:drawToyHUD(game, menuOpen)
    self:drawToyTop(game, menuOpen)
    self:drawToyPause(game)
    self:drawToyRestart(game)
    self:drawToyGoals(game)
    self:drawToyAlerts(game)
    self:drawToyToast()
end

-- Taps on the HUD: a button id, or nil.
function UI:toyButtonAt(vx, vy)
    for i = #self.topButtons, 1, -1 do
        local b = self.topButtons[i]
        if hit(b, vx, vy) then return b.id end
    end
    return nil
end

-- The menu sheet ---------------------------------------------------------------

-- A Toybox sheet: a cream plate in the middle over a dimmed meadow. Returns x, y, w, h.
function UI:sheet(w, h)
    love.graphics.setColor(40 / 255, 28 / 255, 18 / 255, 0.45)
    love.graphics.rectangle('fill', 0, 0, self.vw, self.vh)
    w, h = math.min(w, self.vw - 2 * GUT), math.min(h, self.vh - 2 * GUT)
    local x, y = math.floor((self.vw - w) / 2), math.floor((self.vh - h) / 2)
    Toy.plate(x, y, w, h)
    return x, y, w, h
end

local MIXER = { { 'music', 'Music' }, { 'sfx', 'Effects' }, { 'alert', 'Alerts' } }
UI.TESTER_TOOLS = {
    { 'export', 'export', 'Export' }, { 'history', 'history', 'History' }, { 'fingers', 'finger', 'Fingers' },
    { 'tamatest', 'egg', 'Baby test' }, { 'stockup', 'plus', 'Stock up' }, { 'tiles', 'grass', 'Tiles' }, { 'news', 'chat', 'News' },
}

-- The menu: Carry on, sound, this meadow, the tester corner. Two columns on
-- a wide screen; the body scrolls when the screen is too short for it.
-- confirm: nil, or 'restart' / 'title' while asking once.
function UI:drawToyMenu(game, confirm, fingerDebug)
    self.panelButtons = {}
    local scroll = self.menuScroll or 0
    local buttons = {}
    local function btn(id, r) buttons[#buttons + 1] = { id = id, x = r.x, y = r.y, w = r.w, h = r.h } end
    local twoCols = self.vw >= 900
    local colW = twoCols and 420 or math.min(460, self.vw - 2 * GUT - 36)
    local secH = Toy.height(Toy.S, true) + 18
    local level = game.mode == 'arcade' or game.mode == 'level'
    local tools = UI.TESTER_TOOLS
    local perRow = math.max(1, math.floor((colW + 6) / (72 + 6)))
    local toolRowH = TAP + 8 + Toy.height(Toy.S, true) + 10
    local toolRows = math.ceil(#tools / perRow)

    -- each block: its height, and how to draw it at (x, y) in a column colW wide
    local blocks = {}
    blocks[#blocks + 1] = { h = TAP + 12, draw = function(x, y)
        local carry = { x = x, y = y, w = colW, h = TAP }
        self:toyRow(carry, 'Carry on', 'play', true)
        btn('carryon', carry)
    end }
    blocks[#blocks + 1] = { h = TAP + 8 + #MIXER * (TAP + 4) + 8, draw = function(x, y)
        Toy.text('SOUND', x, y + (TAP - Toy.height(Toy.S, true)) / 2, Toy.S, C.inkSoft, true)
        local mw = Toy.width(game.muted and 'Muted' or 'Mute', Toy.M, true) + Toy.ICON + 44
        local mute = { x = x + colW - mw, y = y, w = mw, h = TAP }
        self:toyRow(mute, game.muted and 'Muted' or 'Mute', 'sound', game.muted)
        btn('mute', mute)
        local cy = y + TAP + 8
        local labelW = 90
        local pctW = Toy.width('100%', Toy.M, true)
        for _, row in ipairs(MIXER) do
            local channel = row[1]
            local v = Audio.getVolume(channel)
            Toy.text(row[2], x, cy + (TAP - Toy.height(Toy.M, true)) / 2, Toy.M, game.muted and C.inkSoft or C.ink, true)
            local minus = { x = x + labelW, y = cy, w = TAP, h = TAP }
            local plus = { x = x + colW - pctW - 8 - TAP, y = cy, w = TAP, h = TAP }
            local bar = { x = minus.x + TAP + 10, y = cy, w = plus.x - 10 - (minus.x + TAP + 10), h = TAP }
            Toy.button(minus, {})
            Toy.button(plus, {})
            Toy.set(C.ink)
            love.graphics.setLineWidth(4)
            love.graphics.line(minus.x + 18, minus.y + TAP / 2, minus.x + TAP - 18, minus.y + TAP / 2)
            love.graphics.line(plus.x + 18, plus.y + TAP / 2, plus.x + TAP - 18, plus.y + TAP / 2)
            love.graphics.line(plus.x + TAP / 2, plus.y + 18, plus.x + TAP / 2, plus.y + TAP - 18)
            local by = bar.y + TAP / 2 - 7
            Toy.set(C.plate2)
            Toy.rrect('fill', bar.x, by, bar.w, 14, 7)
            if v > 0 then
                Toy.set(game.muted and C.inkSoft or C.leaf)
                Toy.rrect('fill', bar.x, by, math.max(14, bar.w * v), 14, 7)
            end
            Toy.set(C.ink)
            love.graphics.setLineWidth(2)
            Toy.rrect('line', bar.x, by, bar.w, 14, 7)
            love.graphics.setLineWidth(1)
            local pct = math.floor(v * 100 + 0.5) .. '%'
            Toy.text(pct, x + colW - Toy.width(pct, Toy.M, true), cy + (TAP - Toy.height(Toy.M, true)) / 2, Toy.M, C.ink, true)
            btn('vol:' .. channel .. ':-', minus)
            btn('vol:' .. channel .. ':+', plus)
            btn('volbar:' .. channel, bar)
            cy = cy + TAP + 4
        end
    end }
    local meadowRows = level and 3 or 2
    blocks[#blocks + 1] = { h = secH + meadowRows * (TAP + 12), draw = function(x, y)
        Toy.text(level and 'THIS LEVEL' or 'THIS MEADOW', x, y + 8, Toy.S, C.inkSoft, true)
        local cy = y + secH
        local function rowOrAsk(id, label, icon, ask)
            if confirm == id then
                local half = math.floor((colW - 8) / 2)
                local yes, no = { x = x, y = cy, w = half, h = TAP }, { x = x + half + 8, y = cy, w = colW - half - 8, h = TAP }
                self:toyRow(yes, ask, icon, false)
                self:toyRow(no, 'Stay', 'play', true)
                btn('confirm:yes', yes)
                btn('confirm:no', no)
            else
                local r = { x = x, y = cy, w = colW, h = TAP }
                self:toyRow(r, label, icon, false)
                btn(id, r)
            end
            cy = cy + TAP + 12
        end
        rowOrAsk('restart', 'Start over', 'restart', 'Yes, start over')
        rowOrAsk('title', 'Back to the title', 'home', 'Yes, go back')
        if level then
            local r = { x = x, y = cy, w = colW, h = TAP }
            self:toyRow(r, 'The goal', 'check', false)
            btn('goal', r)
        end
    end }
    blocks[#blocks + 1] = { h = secH + toolRows * toolRowH, draw = function(x, y)
        Toy.text('TESTER CORNER', x, y + 8, Toy.S, C.inkSoft, true)
        local cell = math.floor((colW + 6) / perRow) - 6
        for i, t in ipairs(tools) do
            local c, rr = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local cx = x + c * (cell + 6)
            local ry = y + secH + rr * toolRowH
            local b = { x = cx + (cell - TAP) / 2, y = ry, w = TAP, h = TAP }
            local on = (t[1] == 'fingers' and fingerDebug) or (t[1] == 'tiles' and game.tileset == 'rogue')
            Toy.button(b, { icon = t[2], on = on })
            local lw = Toy.width(t[3], Toy.S, true)
            Toy.text(t[3], cx + (cell - lw) / 2, ry + TAP + 8, Toy.S, C.ink, true)
            btn(t[1], b)
        end
    end }

    -- columns: the first two blocks on the left, the rest on the right
    local cols = twoCols and { { blocks[1], blocks[2] }, { blocks[3], blocks[4] } } or { blocks }
    local bodyH = 0
    for _, col in ipairs(cols) do
        local hh = 0
        for _, b in ipairs(col) do hh = hh + b.h end
        bodyH = math.max(bodyH, hh)
    end
    local headH = 18 + TAP + 12
    local w = #cols * colW + (#cols - 1) * 32 + 36
    local x, y, pw, ph = self:sheet(w, headH + bodyH + 18)
    Toy.text('Menu', x + 18, y + 18 + (TAP - Toy.height(Toy.L, true)) / 2, Toy.L, C.ink, true)
    local close = { x = x + pw - 18 - TAP, y = y + 18, w = TAP, h = TAP }
    Toy.button(close, { icon = 'close' })
    self.panelButtons[#self.panelButtons + 1] = { id = 'carryon', x = close.x, y = close.y, w = close.w, h = close.h }
    -- the body, scrolled and clipped to the sheet
    local top, bottom = y + headH, y + ph - 12
    local room = bottom - top
    self.menuScrollMax = math.max(0, bodyH + 6 - room)
    scroll = Util.clamp(scroll, 0, self.menuScrollMax)
    self.menuScroll = scroll
    local s = self.scale
    love.graphics.setScissor(math.floor(x * s), math.floor(top * s), math.ceil(pw * s), math.ceil(room * s))
    for ci, col in ipairs(cols) do
        local cx = x + 18 + (ci - 1) * (colW + 32)
        local cy = top - scroll
        for _, b in ipairs(col) do
            b.draw(cx, cy)
            cy = cy + b.h
        end
    end
    love.graphics.setScissor()
    if self.menuScrollMax > 0 then
        -- a little bar says there is more
        local trackH = room - 8
        local barH = math.max(40, trackH * room / (bodyH + 6))
        local by = top + 4 + (trackH - barH) * scroll / self.menuScrollMax
        Toy.set(C.inkSoft, 0.5)
        Toy.rrect('fill', x + pw - 9, by, 5, barH, 3)
    end
    for _, b in ipairs(buttons) do
        -- only what can be seen can be pressed
        if b.y + b.h > top and b.y < bottom then
            local cut = { id = b.id, x = b.x, y = math.max(b.y, top), w = b.w, h = math.min(b.y + b.h, bottom) - math.max(b.y, top) }
            self.panelButtons[#self.panelButtons + 1] = cut
        end
    end
    self.menuSheet = { x = x, y = y, w = pw, h = ph, top = top, bottom = bottom }
end

function UI:insideMenu(vx, vy) return hit(self.menuSheet, vx, vy) end

end
