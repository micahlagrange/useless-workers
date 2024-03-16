local UI = require('src.system.ui')


function love.mousereleased(x, y, button)
    x, y = Camera:mousePosition()
    UI.mouseUp(x, y, button, x, y)
end

function love.mousepressed(x, y, button)
    x, y = Camera:mousePosition()
    UI.mouseDown(x, y, button, x, y)
end

function love.mousemoved(x, y, dx, dy, istouch)
    --local mx, my = Camera:mousePosition()
end
