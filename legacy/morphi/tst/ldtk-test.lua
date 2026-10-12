local lu = require('libs.luaunit')
require('src.constants')
love = require('tst.mocks.lovemock')

-- Require the library
local ldtk = require 'libs.ldtk'


-- Override the callbacks with your game logic.
function ldtk.onEntity(entity)
    -- A new entity is created.
    lu.assertIsTrue(type(entity.iid) == "string")
end

function ldtk.onLayer(layer)
    -- A new layer is created.
    --[[ 
        The "layer" object has a draw function to draw the whole layer.
        Used like:
            layer:draw()
    ]]
end

function ldtk.onLevelLoaded(level)
    -- Current level is about to be changed.
end

function ldtk.onLevelCreated(level)
    -- Current level has changed.
end

-- Load the .ldtk file
ldtk:load('./tst/data/test.ldtk')
-- Flip the loading order if needed.
ldtk:setFlipped(true) --false by default

-- Load a level
ldtk:goTo(1)        --loads the second level
ldtk:level('AutoLayer')   --loads the level named cat
ldtk:next()         --loads the next level (or the first if we are in the last)
ldtk:previous()     --loads the previous level (or the last if we are in the first)
ldtk:reload()       --reloads the current level
