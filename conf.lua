-- Debug switches
DEBUG = false
UI_DEBUG = false
PATH_DEBUG = false
CLICK_DEBUG = false

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 800

-- tools/shot.lua: desktop screenshots for development (lovec . --shot steps.lua [outdir])
for i, a in ipairs(arg or {}) do
    if a == '--shot' then
        SHOT_SCRIPT, SHOT_OUT = arg[i + 1], arg[i + 2]
        TEST_HOOKS = TEST_HOOKS or {}
    end
end

function love.conf(t)
    t.title = "Morphis"
    t.identity = "morphis" -- the save folder; on itch every love.js game shares one IndexedDB
    t.version = "11.4" -- 11.4 keeps makelove and love.js happy, the API we use is identical in 11.5
    t.console = false
    t.window.width = WINDOW_WIDTH   -- the starting size; the HUD lays itself out for any size after that
    t.window.height = WINDOW_HEIGHT
    t.window.vsync = 1
    t.window.resizable = true
    t.window.minwidth = 480
    t.window.minheight = 320
end
