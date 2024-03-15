local UI = require('src.system.ui')
local mousePointer = World:newBSGRectangleCollider(0, 0, 5, 5, 0)
mousePointer:setCollisionClass(CollisionClasses.GHOST)


function love.mousereleased(x, y, button)
    x, y = normalize_on_zoom(x, y)
    print("Mouse " .. "button " .. button .. " released at: " .. x .. ", " .. y)
    if button == INPUT.Mouse.LMB or button == INPUT.Mouse.RMB then
        UI.click(mousePointer, button, x, y)
    end
end

function love.mousepressed(x, y, button)
    x, y = normalize_on_zoom(x, y)
    print("Mouse " .. "button " .. button .. " pressed at: " .. x .. ", " .. y)
end

function love.mousemoved(x, y, dx, dy, istouch)
    x, y = normalize_on_zoom(x, y)
    mousePointer.x, mousePointer.y = x, y
end

function normalize_on_zoom(x, y)
    return x / CAMERA_ZOOM_LEVEL, y / CAMERA_ZOOM_LEVEL
end
