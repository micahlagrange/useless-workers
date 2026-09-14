-- Screen shake and expanding explosion rings, all in world space.
local tween = require('libs.tween')

local Effects = {}
local rings = {}
local shakeT, shakeDuration, shakeMagnitude = 0, -1, 0

function Effects.shake(duration, magnitude)
    shakeT, shakeDuration, shakeMagnitude = 0, duration or 0.4, magnitude or 6
end

function Effects.explosion(wx, wy, maxSize, color, duration)
    local ring = { x = wx, y = wy, size = 2, alpha = 0.7, color = color or { 1, 0.6, 0.2 } }
    ring.tween = tween.new(duration or 0.35, ring, { size = maxSize or 40, alpha = 0 }, 'outQuad')
    rings[#rings + 1] = ring
end

function Effects.update(dt)
    if shakeT < shakeDuration then shakeT = shakeT + dt end
    for i = #rings, 1, -1 do
        if rings[i].tween:update(dt) then table.remove(rings, i) end
    end
end

function Effects.applyShake()
    if shakeT < shakeDuration then
        local dx = love.math.random(-shakeMagnitude, shakeMagnitude)
        local dy = love.math.random(-shakeMagnitude, shakeMagnitude)
        love.graphics.translate(dx, dy)
    end
end

function Effects.draw()
    for _, r in ipairs(rings) do
        love.graphics.setColor(r.color[1], r.color[2], r.color[3], r.alpha)
        love.graphics.setLineWidth(2)
        love.graphics.circle('line', r.x, r.y, r.size)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function Effects.clear()
    rings = {}
    shakeDuration = -1
end

return Effects
