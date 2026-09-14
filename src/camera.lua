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
    self.minScale = 0.8
    self.maxScale = 4
    return self
end

function Camera:clamp()
    local visibleW = self.viewW / self.scale
    local visibleH = self.viewH / self.scale
    if visibleW >= self.worldPxW then
        self.x = (self.worldPxW - visibleW) / 2
    else
        self.x = Util.clamp(self.x, 0, self.worldPxW - visibleW)
    end
    if visibleH >= self.worldPxH then
        self.y = (self.worldPxH - visibleH) / 2
    else
        self.y = Util.clamp(self.y, 0, self.worldPxH - visibleH)
    end
end

function Camera:centerOn(wx, wy)
    self.x = wx - self.viewW / 2 / self.scale
    self.y = wy - self.viewH / 2 / self.scale
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
