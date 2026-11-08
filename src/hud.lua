-- The ring on screen: where it sits, how it draws, the tapped square's
-- highlight, the caption plate, presses and holds. main.lua owns what the
-- items do (hud.onAct). Draws in the HUD's virtual space.
require('src.constants')
local Toy = require('src.toy')
local Ring = require('src.ring')
local JobSets = require('src.jobsets')

local Hud = {}
Hud.__index = Hud

local C = Toy.C
local CAPTION_FLASH = 2.6

function Hud.new(ui)
    local self = setmetatable({}, Hud)
    self.ui = ui
    self.ring = nil      -- the open ring's spec
    self.caption = nil   -- { title, line, said, hint }
    self.captionTtl = 0  -- > 0: a caption on its own that fades (a bush, a tree)
    self.preview = nil   -- the build kind a hovered or pressed button would set out
    self.press = nil     -- { item, t, held }
    self.openedAt = 0
    self.onAct = nil     -- function(item, hold)
    return self
end

function Hud:isOpen() return self.ring ~= nil end

function Hud:open(spec, now)
    self.ring = spec
    self.caption = spec.caption
    self.captionTtl = 0
    self.preview = nil
    self.press = nil
    self.openedAt = now or 0
    self.nudged = false
end

function Hud:close()
    self.ring = nil
    self.press = nil
    self.preview = nil
    if self.captionTtl <= 0 then self.caption = nil end
end

function Hud:flash(caption)
    self:close()
    self.caption = caption
    self.captionTtl = CAPTION_FLASH
end

-- The ring's centre on screen, in virtual pixels.
function Hud:anchor(game)
    local spec = self.ring
    if not spec then return nil end
    local cam, s = game.camera, self.ui.scale
    if spec.worker then
        local p = cam:toScreen(spec.worker.x, spec.worker.y - 2)
        return p.x / s, p.y / s
    end
    local t = spec.tile
    local p = cam:toScreen((t.x - 1 + t.w / 2) * TILE_SIZE, (t.y - 1 + t.h / 2) * TILE_SIZE)
    return p.x / s, p.y / s
end

-- The tapped thing's box on screen (virtual): a tile rect, or a circle round a morphi.
function Hud:pickShape(game)
    local spec = self.ring
    if not spec then return nil end
    local cam, s = game.camera, self.ui.scale
    if spec.worker then
        local w = spec.worker
        local p = cam:toScreen(w.x, w.y - 3)
        return { circle = true, x = p.x / s, y = p.y / s, r = (w:isBaby() and 10 or 13) * cam.scale / s + 8 }
    end
    local t = spec.tile
    local a = cam:toScreen((t.x - 1) * TILE_SIZE, (t.y - 1) * TILE_SIZE)
    local b = cam:toScreen((t.x - 1 + t.w) * TILE_SIZE, (t.y - 1 + t.h) * TILE_SIZE)
    return { x = a.x / s, y = a.y / s, w = (b.x - a.x) / s, h = (b.y - a.y) / s }
end

-- Lay out the open ring's buttons around the anchor. Returns them.
function Hud:layout(game)
    local spec = self.ring
    if not spec then return {} end
    local ax, ay = self:anchor(game)
    local items = spec.items
    if spec.kind == 'home' then items = self.homeItems or {} end
    local offs = Ring.offsets(#items, Toy.TAP)
    local tap = Toy.TAP
    local btns = {}
    for i, it in ipairs(items) do
        local o = offs[i]
        btns[#btns + 1] = { item = it, up = o.up, x = ax + o.x - tap / 2, y = ay + o.y - tap / 2, w = tap, h = tap }
    end
    if spec.center then
        local c = 52
        btns[#btns + 1] = { item = spec.center, center = true, x = ax - c / 2, y = ay - c / 2, w = c, h = c }
    end
    self.buttons = btns
    return btns
end

-- How far the camera has to move (screen pixels) so the ring and caption fit.
function Hud:fitShift(game, top)
    local spec = self.ring
    if not spec then return 0, 0 end
    local ax, ay = self:anchor(game)
    local items = spec.kind == 'home' and (self.homeItems or {}) or spec.items
    local R = Ring.radius(math.max(1, #items), Toy.TAP) + 60
    local vw, vh = self.ui.vw, self.ui.vh
    local capH = self.captionH or 90
    local minX, maxX = R - 20, vw - R + 20
    local minY, maxY = (top or 0) + R, vh - R - capH + 10
    local dx, dy = 0, 0
    if ax < minX then dx = ax - minX elseif ax > maxX then dx = ax - maxX end
    if maxY < minY then dy = ay - (minY + maxY) / 2 elseif ay < minY then dy = ay - minY elseif ay > maxY then dy = ay - maxY end
    return dx * self.ui.scale, dy * self.ui.scale
end

function Hud:buttonAt(vx, vy)
    if not self.ring then return nil end
    for i = #(self.buttons or {}), 1, -1 do
        local b = self.buttons[i]
        if Toy.hit(b, vx, vy) then return b end
    end
    return nil
end

-- A press on a ring button: true when the ring took it.
function Hud:pressed(vx, vy, now)
    local b = self:buttonAt(vx, vy)
    if not b then return false end
    self.press = { item = b.item, t = now, held = false, b = b }
    if b.item.preview then self.preview = b.item.preview end
    return true
end

-- Called every frame: a press held long enough is a hold.
function Hud:update(dt, now)
    if self.captionTtl > 0 then
        self.captionTtl = self.captionTtl - dt
        if self.captionTtl <= 0 and not self.ring then self.caption = nil end
    end
    local p = self.press
    if p and not p.held and p.item.hold and now - p.t >= Ring.HOLD_SECONDS then
        p.held = true
        if self.onAct then self.onAct(p.item, true) end
    end
end

-- A release: a tap on the button it was pressed on. Returns true if taken.
function Hud:released(vx, vy)
    local p = self.press
    if not p then return false end
    self.press = nil
    if p.held then return true end
    local b = self:buttonAt(vx, vy)
    if b and b.item == p.item and self.onAct then self.onAct(p.item, false) end
    return true
end

-- The mouse over a build button shows what it would set out.
function Hud:hover(vx, vy)
    if not self.ring or self.press then return end
    local b = self:buttonAt(vx, vy)
    self.preview = b and b.item.preview or nil
end

-- Drawing ------------------------------------------------------------------

local function drawPick(shape, time, preview)
    local vw, vh = love.graphics.getDimensions()
    vw, vh = vw * 4, vh * 4 -- the dim covers everything; the HUD scale is applied
    local pulse = (math.sin(time / 0.22) + 1) / 2
    love.graphics.setColor(40 / 255, 28 / 255, 18 / 255, 0.4)
    if shape.circle then
        love.graphics.stencil(function() love.graphics.circle('fill', shape.x, shape.y, shape.r) end, 'replace', 1)
        love.graphics.setStencilTest('notequal', 1)
        love.graphics.rectangle('fill', -vw, -vh, vw * 2, vh * 2)
        love.graphics.setStencilTest()
    else
        local x, y, w, h = shape.x, shape.y, shape.w, shape.h
        love.graphics.rectangle('fill', -vw, -vh, vw * 2, y + vh)          -- above
        love.graphics.rectangle('fill', -vw, y + h, vw * 2, vh * 2)        -- below
        love.graphics.rectangle('fill', -vw, y, x + vw, h)                 -- left
        love.graphics.rectangle('fill', x + w, y, vw * 2, h)               -- right
        if not preview then
            love.graphics.setColor(C.sun[1], C.sun[2], C.sun[3], 0.16 + pulse * 0.14)
            love.graphics.rectangle('fill', x, y, w, h)
        end
    end
    local function outline(g, r)
        if shape.circle then love.graphics.circle('line', shape.x, shape.y, shape.r + g)
        else Toy.rrect('line', shape.x - g, shape.y - g, shape.w + g * 2, shape.h + g * 2, r) end
    end
    love.graphics.setLineWidth(8)
    Toy.set(C.ink)
    outline(2, 10)
    love.graphics.setLineWidth(4.5)
    Toy.set(C.sun)
    outline(2, 10)
    if not Hud.calm then
        local g = 6 + pulse * 8
        love.graphics.setLineWidth(3)
        love.graphics.setColor(C.sun[1], C.sun[2], C.sun[3], (1 - pulse) * 0.9)
        outline(g, 13)
    end
    love.graphics.setLineWidth(1)
end

function Hud:drawRing(game, time)
    if not self.ring then return end
    local shape = self:pickShape(game)
    if shape then drawPick(shape, time, self.preview ~= nil and not shape.circle) end
    local btns = self:layout(game)
    local grow = math.min(1, (time - self.openedAt) / 0.18)
    local ax, ay = self:anchor(game)
    for _, b in ipairs(btns) do
        local it = b.item
        local k = Hud.calm and 1 or (0.3 + 0.7 * grow)
        local r = { x = ax + (b.x - ax) * k, y = ay + (b.y - ay) * k, w = b.w, h = b.h }
        local pressed = self.press and self.press.item == it
        local fill = it.neutral and C.leaf2 or it.color or nil
        Toy.button(r, { icon = it.icon, on = it.on, off = it.off, round = b.center or it.face, pressed = pressed, fill = fill,
            badge = it.badge, badgeColor = it.badgeColor and C[it.badgeColor] or (it.neutral and C.leaf) or nil, bar = it.bar })
        if it.face then
            -- a blob's face: two eyes on its colour
            Toy.set(C.ink)
            love.graphics.ellipse('fill', r.x + 20, r.y + 24, 3.5, 5)
            love.graphics.ellipse('fill', r.x + r.w - 20, r.y + 24, 3.5, 5)
        end
        if self.press and self.press.item == it and it.hold and not self.press.held then
            local p = math.min(1, (time - self.press.t) / Ring.HOLD_SECONDS)
            love.graphics.setColor(C.leaf[1], C.leaf[2], C.leaf[3], 0.35)
            Toy.rrect('fill', r.x, r.y + r.h * (1 - p), r.w, r.h * p, Toy.R)
        end
        if self.preview and it.preview == self.preview and not b.center then
            love.graphics.setLineWidth(4)
            Toy.set(C.sun)
            Toy.rrect('line', r.x - 4, r.y - 4, r.w + 8, r.h + 8, Toy.R + 4)
            love.graphics.setLineWidth(1)
        end
        if it.label and grow >= 1 then
            local lh = Toy.height(Toy.S, true) + 4
            local ly = b.up and (r.y - 8 - lh) or (r.y + r.h + 8)
            Toy.labelPlate(it.label, r.x + r.w / 2, ly, Toy.S, it.cost, it.off and C.berry or C.inkSoft)
        end
    end
end

-- The caption plate at the bottom: what was tapped.
function Hud:drawCaption()
    local c = self.caption
    if not c then self.captionH = 0 return end
    local ui = self.ui
    local w = math.min(580, ui.vw - 2 * Toy.GUTTER)
    local pad = 16
    local inner = w - 2 * pad
    local h = pad - 4
    local titleH = Toy.height(Toy.M, true)
    h = h + titleH
    local lineH = c.line and c.line ~= '' and (#Toy.wrap(c.line, inner, Toy.S) * (Toy.height(Toy.S) + 2)) or 0
    local saidH = c.said and (#Toy.wrap(c.said, inner - 20, Toy.S) * (Toy.height(Toy.S) + 2) + 12) or 0
    local hintH = c.hint and (#Toy.wrap(c.hint, inner, Toy.S) * (Toy.height(Toy.S) + 2)) or 0
    h = h + (lineH > 0 and lineH + 2 or 0) + (saidH > 0 and saidH + 4 or 0) + (hintH > 0 and hintH + 4 or 0) + pad - 2
    local x, y = math.floor((ui.vw - w) / 2), ui.vh - Toy.GUTTER - h
    self.captionH = h + Toy.GUTTER
    local alpha = self.captionTtl > 0 and math.min(1, self.captionTtl / 0.3) or 1
    if alpha < 1 then love.graphics.push('all') end
    Toy.plate(x, y, w, h)
    local cy = y + pad - 4
    local tw = Toy.text(c.title, x + pad, cy, Toy.M, C.ink, true)
    if c.sub then Toy.text(c.sub, x + pad + tw + 8, cy + (titleH - Toy.height(Toy.S)) / 2, Toy.S, C.inkSoft) end
    cy = cy + titleH + 2
    if lineH > 0 then cy = cy + Toy.para(c.line, x + pad, cy, inner, Toy.S, C.ink) + 4 end
    if saidH > 0 then
        Toy.set(C.plate2)
        Toy.rrect('fill', x + pad, cy, inner, saidH, 12)
        Toy.para(c.said, x + pad + 10, cy + 6, inner - 20, Toy.S, C.ink)
        cy = cy + saidH + 4
    end
    if hintH > 0 then Toy.para(c.hint, x + pad, cy, inner, Toy.S, C.inkSoft) end
    if alpha < 1 then love.graphics.pop() end
end

-- Each species' colour, for its face on a button.
local SPECIES_COLOR = { pupper = 'F2C27B', woofoof = '8FD3F0', twins = 'F59AC0', cwab = 'EF6B5B', blue = 'C7A6F2', ribbit = '8FD16A' }
function Hud.workerColor(w)
    local h = SPECIES_COLOR[w.sheet] or 'F2C27B'
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 }
end

-- A morphi's caption: who, what it is doing, how it feels, its jobs.
function Hud.workerCaption(w)
    local bits = { w:describeState() }
    if not w.arcade then bits[#bits + 1] = w:hungerStatus() end
    if w.jobSet then bits[#bits + 1] = 'not keen on ' .. JobSets.label(w.jobSet.disliked):lower() .. ' work' end
    local hint = w.jobSet and 'Tap a job: first job (1). Hold, or right click: then, when there is nothing (2). The eye: follow.'
        or 'The eye: follow.'
    return { title = w.name, sub = 'the ' .. w.species, line = table.concat(bits, ' · '), hint = hint }
end

return Hud
