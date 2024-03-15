local food = require('src.needs.food')
local GameObjects = require('src.system.gameobjects')
UI = {}


local function cleanEatenFood()
    local toClean = {}
    for i, f in ipairs(GameObjects.get_all_objects()) do
        if type(f) == "food" and f.eaten then
            table.insert(toClean, i)
        end
    end

    for idx, _ in ipairs(toClean) do
        GameObjects.remove(idx)
    end
end

local function addRandomFood(x, y)
    GameObjects.add(food(x, y))
    cleanEatenFood()
end

function UI.click(mousePointer, button, x, y)
    -- mousePointer is the windfield collision rect you can use to detect what the mouse clicked on if you need to
    addRandomFood(x, y)
    return
end

return UI
