local UI = require('src.system.ui')

local Mouse = {}

function love.mousereleased(x, y, button)
    x, y = Camera:mousePosition()
    UI.mouseUp(x, y, button, x, y)
end

function love.mousepressed(x, y, button)
    x, y = Camera:mousePosition()
    UI.mouseDown(x, y, button, x, y)
end

-- function love.mousemoved(x, dddy, dx, dy, istouch)
-- end

function Mouse.debug()
    -- Draw the mouse's position
    local mouseX, mouseY = love.mouse.getPosition()
    --Camera:mousePosition()
    love.graphics.setColor(0, 1, 0) -- green
    love.graphics.circle('fill', mouseX, mouseY, 5)

    -- Reset color
    love.graphics.setColor(1, 1, 1)
end

return Mouse
