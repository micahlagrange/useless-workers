love.graphics.setDefaultFilter("nearest", "nearest")

require('constants')

-- requires
local worker = require('worker')
local mapgen = require('mapgen')

-- tilemap objects
local spawnPoints = {}
local workers = {}

function love.load(args)
    args.tilemap = args.tilemap or 'spritesheets/swampy.lua'

    print('args', args, args.tilemap)
    PrettyPrint(args)

    local hump = require('libs/camera')
    local sti = require('libs/sti')
    local wf = require('libs/windfield')
    SFX = require('audio')
    Anim8 = require('libs/anim8')

    -- resource globals
    GameMap = sti(args.tilemap)
    Camera = hump()
    Camera:zoomTo(2)
    World = wf.newWorld(0, GRAVITY)

    World:addCollisionClass(COLLISION_WORKER)
    World:addCollisionClass(COLLISION_GROUND)
    World:addCollisionClass(COLLISION_GHOST, { ignore = { COLLISION_GROUND, COLLISION_WORKER } })

    spawnPoints = mapgen.GenerateMapObjects('Spawn', COLLISION_GHOST, { gravityDisabled = true })
    mapgen.GenerateMapObjects('Ground', COLLISION_GROUND, { colliderType = 'static' })

    for _, sp in ipairs(spawnPoints) do
        table.insert(workers, worker.NewWorker(sp:getX(), sp:getY()))
    end
end

function love.update(dt)
    for _, w in ipairs(workers) do
        w:update(dt)
    end
end

function love.draw(dt)
    Camera:attach()
    -- reset color, Draw the tilemap
    love.graphics.setColor(1, 1, 1)
    GameMap:drawLayer(GameMap.layers[LAYER_BG])
    GameMap:drawLayer(GameMap.layers[LAYER_PLAYER])

    for _, w in ipairs(workers) do
        w:draw(dt)
    end
    Camera:lookAt(workers[1].x, workers[1].y)
    Camera:detach()
end
