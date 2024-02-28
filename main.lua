-- lib requires
SFX = require('src.audio')
Anim8 = require('libs/anim8')
local hump = require('libs/camera')
local wf = require('libs/windfield')
-- resource globals
Camera = hump.new(0, 0, 0, 0, hump.smooth.linear(3))
Camera:zoomTo(4)
World = wf.newWorld(0, GRAVITY)
local inspect = require('libs.inspect')
-- ldtk
local ldtk = require('libs.ldtk')

-- src requires
local worker = require('src.worker')
local Layer = require('src.drawing.layer')
local collision = require('src.collision')
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
    print('layer ', layer.id)
    -- Here we treated the layer as an object and added it to the table we use to draw.
    -- Generally, you would create a new object and use that object to draw the layer.
    table.insert(gameobjects, Layer(layer)) --adding layer to the table we use to draw
    print(#gameobjects)
end

function ldtk.onLevelLoaded(level)
    print('level ', level.id)

    --removing all objects so we have a blank level
    gameobjects = {}

    --changing background color to the one defined in LDtk
    love.graphics.setBackgroundColor(level.backgroundColor)
    --draw a bunch of rectangles
    collision:new()
    collision:loadJSON()
    collision:IntGridToWinfieldRects(collision:findIntGrid())
    print(#gameobjects)
end

function ldtk.onEntity(entity)
    print(string.format('entity id:%s x:%s y:%s width:%s height:%s props:%s visible:%s',
        entity.id, entity.x, entity.y, entity.width, entity.height,
        inspect(entity.props), entity.visible))

    if entity.id == 'Morphi' then
        local w = worker:new(entity)
        table.insert(gameobjects, w)
        print(#gameobjects)
    end
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

    for _, obj in ipairs(gameobjects) do
        obj:draw()
        if obj.name and obj.name == 'Jammy' then
            Camera:lookAt(obj.x, obj.y)
        end
    end

    --World:draw()

    Camera:detach()
end
