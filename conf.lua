-- Debug switches
DEBUG = false
UI_DEBUG = false
PATH_DEBUG = false
CLICK_DEBUG = false

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 800

function love.conf(t)
    t.title = "Human Resources"
    t.version = "11.4" -- 11.4 keeps makelove and love.js happy, the API we use is identical in 11.5
    t.console = false
    t.window.width = WINDOW_WIDTH
    t.window.height = WINDOW_HEIGHT
    t.window.vsync = 1
    t.window.resizable = false
end
