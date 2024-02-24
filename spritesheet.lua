require('constants')

-- takes a spritesheet
local spritesheet = {}
function spritesheet.NewAnim8Grid(spriteSheet, w, h)
    return Anim8.newGrid(
        w,
        h,
        spriteSheet:getWidth(),
        spriteSheet:getHeight()
    )
end

-- Takes a love.graphics.newImage('somepath') and returns a table of quads
function SpriteSheetToQuads(spritesheet, spriteWidth, spriteHeight)
    -- Get the total number of sprites in the spritesheet
    local spritesheetWidth = spritesheet:getWidth()
    local spritesheetHeight = spritesheet:getHeight()

    -- Calculate the number of columns and rows in the spritesheet
    local columns = spritesheetWidth / spriteWidth
    local rows = spritesheetHeight / spriteHeight

    -- Create a table to hold the Quads
    local quads = {}

    for y = 0, rows - 1 do
        for x = 0, columns - 1 do
            -- Create a new Quad for each sprite
            local quad = love.graphics.newQuad(
                x * spriteWidth,
                y * spriteHeight,
                spriteWidth,
                spriteHeight,
                spritesheetWidth,
                spritesheetHeight)
            table.insert(quads, quad)
        end
    end

    return quads
end

return spritesheet
