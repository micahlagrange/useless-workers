require('src.constants')
local Util = require('src.util')

local Camera = {}
Camera.__index = Camera

function Camera.new(worldW, worldH, viewW, viewH)
    local self = setmetatable({}, Camera)
    self.x, self.y = 0, 0
    self.scale = 1.5
    self.worldPxW = worldW * TILE_SIZE
    self.worldPxH = worldH * TILE_SIZE
    self.viewW, self.viewH = viewW, viewH
    self.minScale = 0.5
    self.maxScale = 4
    self.insetTop, self.insetBottom = 0, 0
    self:setView(viewW, viewH)
    return self
end

-- The HUD bars cover the top and bottom of the screen (in screen pixels);
-- the map scrolls and centres in the strip between them.
function Camera:setInsets(top, bottom)
    self.insetTop, self.insetBottom = top or 0, bottom or 0
    self:clamp()
end

function Camera:availH()
    return math.max(50, self.viewH - self.insetTop - self.insetBottom)
end

-- Zoom so the whole world fits between the bars, then centre. For the hand
-- built levels, which are small.
function Camera:fitWorld()
    local s = math.min(self.viewW / self.worldPxW, self:availH() / self.worldPxH)
    self.scale = Util.clamp(math.floor(s * 4) / 4, self.minScale, self.maxScale)
    self:centerOn(self.worldPxW / 2, self.worldPxH / 2)
end

-- Zooming in stops when about seven tiles span the screen: close enough to
-- read a morphi's face, not so close it is one giant tree.
function Camera:setView(w, h)
    self.viewW, self.viewH = w, h
    self.maxScale = Util.clamp(math.min(w, h * 1.6) / (7 * TILE_SIZE), 2, 12)
    self.scale = Util.clamp(self.scale, self.minScale, self.maxScale)
    self:clamp()
end

function Camera:clamp()
    local visibleW = self.viewW / self.scale
    local visibleH = self:availH() / self.scale
    local top = self.insetTop / self.scale -- world units hidden under the top bar
    if visibleW >= self.worldPxW then
        self.x = (self.worldPxW - visibleW) / 2
    else
        self.x = Util.clamp(self.x, 0, self.worldPxW - visibleW)
    end
    -- the world's top edge can come down to the top bar, its bottom edge up
    -- to the bottom bar
    if visibleH >= self.worldPxH then
        self.y = (self.worldPxH - visibleH) / 2 - top
    else
        self.y = Util.clamp(self.y, -top, self.worldPxH - visibleH - top)
    end
end

function Camera:centerOn(wx, wy)
    self.x = wx - self.viewW / 2 / self.scale
    self.y = wy - (self.insetTop + self:availH() / 2) / self.scale
    self:clamp()
end

function Camera:pan(dxScreen, dyScreen)
    self.x = self.x + dxScreen / self.scale
    self.y = self.y + dyScreen / self.scale
    self:clamp()
end

-- Zoom keeping the world point under the mouse fixed.
function Camera:zoomAt(factor, sx, sy)
    local before = self:toWorld(sx, sy)
    self.scale = Util.clamp(self.scale * factor, self.minScale, self.maxScale)
    local after = self:toWorld(sx, sy)
    self.x = self.x + (before.x - after.x)
    self.y = self.y + (before.y - after.y)
    self:clamp()
end

function Camera:apply()
    love.graphics.push()
    love.graphics.scale(self.scale)
    love.graphics.translate(-self.x, -self.y)
end

function Camera:reset()
    love.graphics.pop()
end

function Camera:toWorld(sx, sy)
    return { x = sx / self.scale + self.x, y = sy / self.scale + self.y }
end

function Camera:toScreen(wx, wy)
    return { x = (wx - self.x) * self.scale, y = (wy - self.y) * self.scale }
end

function Camera:toTile(sx, sy)
    local w = self:toWorld(sx, sy)
    return Util.worldToTile(w.x, w.y)
end

return Camera
