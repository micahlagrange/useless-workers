love.graphics.setDefaultFilter("nearest", "nearest")

LEFT = 0
RIGHT = 1
GRAVITY = 1600

TILE_SIZE = 32
PLAYER_SCALE = 1.9

function love.load(args)
    args = args or {
        'default tilemap'
    }
    local hump = require('libs/camera')
    local sti = require('libs/sti')
    local wf = require('libs/windfield')
    -- resource globals
    Anim8 = require('libs/anim8')
    GameMap = sti(args.tilemap)
    Camera = hump()
    Camera:zoomTo(2)
    World = wf.newWorld(0, GRAVITY)
    SFX = require('audio')
    SFX.DrWeeb:setLooping(true)
    SFX.DrWeeb:play()
end

function love.update()
end

function love.draw()
end
