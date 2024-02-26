Object = require('libs.classic')

Layer = Object:extend()

function Layer:new(layer)
    -- setting up the object using the entity data
    self.x, self.y = layer.x, layer.y
    self.w, self.h = layer.width, layer.height
    self.visible = layer.visible
end

function Layer:update()
end

function Layer:draw()
    if self.visible then
        --draw a rectangle to represent the entity
        love.graphics.rectangle('fill', self.x, self.y, self.w, self.h)
    end
end

return Layer