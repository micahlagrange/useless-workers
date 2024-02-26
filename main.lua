-- lib requires
SFX = require('src.audio')
Anim8 = require('libs/anim8')
local hump = require('libs/camera')
local wf = require('libs/windfield')
-- resource globals
Camera = hump.new(0, 0, 0, 0, hump.smooth.linear(3))
Camera:zoomTo(3)
World = wf.newWorld(0, GRAVITY)
local inspect = require('libs.inspect')
-- ldtk
local ldtk = require('libs.ldtk')

-- src requires
local worker = require('src.worker')
local Layer = require('src.drawing.layer')
require('src.constants')

-- tilemap objects
local gameobjects = {}

function love.load()
    --resizing the screen to 512px width and 512px height
    love.window.setMode(800, 640)

    --setting up the project for pixelart
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.graphics.setLineStyle('rough')

    --loading the .ldtk file
    ldtk:load('tilemaps/morphi.ldtk')
    ldtk:setFlipped(true)
    World:addCollisionClass(COLLISION_WORKER)
    World:addCollisionClass(COLLISION_GROUND)
    World:addCollisionClass(COLLISION_GHOST, { ignore = { COLLISION_GROUND, COLLISION_WORKER } })
    World:setGravity(0, GRAVITY)
    ldtk:level('Level_0')
end

function ldtk.onLayer(layer)
    print(inspect('layer ', layer))
    -- Here we treated the layer as an object and added it to the table we use to draw.
    -- Generally, you would create a new object and use that object to draw the layer.
    table.insert(gameobjects, Layer(layer)) --adding layer to the table we use to draw
end

function ldtk.onLevelLoaded(level)
    print(inspect('level ', level))

    --removing all objects so we have a blank level
    gameobjects = {}

    --changing background color to the one defined in LDtk
    love.graphics.setBackgroundColor(level.backgroundColor)
end

function ldtk.onEntity(entity)
    print(string.format('entity id:%s x:%s y:%s width:%s height:%s props:%s visible:%s',
        entity.id, entity.x, entity.y, entity.width, entity.height,
        inspect(entity.props), entity.visible))

    local w = worker:new(entity)
    table.insert(gameobjects, w)
end

function love.update(dt)
    World:update(dt)
    for _, w in ipairs(gameobjects) do
        w:update(dt)
    end
end

function love.draw()
    Camera:attach()

    -- reset color, Draw the tilemap
    love.graphics.setColor(1, 1, 1)

    local morphi
    for _, obj in ipairs(gameobjects) do
        if obj.name == 'Morphi' then
            morphi = obj
        end
        obj:draw()
    end
    Camera:lookAt(morphi.x, morphi.y)

    -- print(Camera.x, Camera.y, morphi.x, morphi.y)
    World:draw()

    Camera:detach()
end
