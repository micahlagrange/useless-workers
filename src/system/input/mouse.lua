local UI = require('src.system.ui')

local Mouse = {}

local cursor = UI.CreateShape(-999, -999, 4, 4)

function love.mousereleased(_, _, button)
    local x, y = Camera:mousePosition()
    UI.mouseUp(x, y, button, x, y)
end

function love.mousepressed(_, _, button)
    local cx, cy = Camera:mousePosition()
    UI.mouseDown(cx, cy, button)
end

function love.mousemoved(_, _, _, _, _)
    local x, y = Camera:mousePosition()
    cursor:getBody():setPosition(Camera:cameraCoords(x, y))
end

function Mouse.debug()
    -- Draw the mouse's position
    love.graphics.setColor(0, 1, 0) -- green
    local body = cursor:getBody()
    local shape = cursor:getShape()
    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))

    -- Reset color
    love.graphics.setColor(1, 1, 1)

    UI.printDebugNearFixture(cursor)
end

love.mouse.setVisible(false)

return Mouse
