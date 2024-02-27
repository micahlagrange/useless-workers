local open    = io.open
local inspect = require('libs.inspect')
local json    = require('libs.json')
local object  = require('libs.classic')


print(_VERSION)

-- class
LDtkParser = object:extend()
function LDtkParser:new(ldtkpath, level, intgridLayerName)
    self.path = ldtkpath or 'tilemaps/morphi.ldtk'
    self.level = level
    self.intgridLayerName = intgridLayerName or 'IntGrid'
end

function LDtkParser:loadJSON()
    local content = self:readFile(self.path)
    self.ldtkJson = json.decode(content)
end

function LDtkParser:findIntGrid51()
    local layers
    if self.level then
        for _, level in ipairs(self.ldtkJson) do
            if level.id == self.level then
                layers = level.layerInstances
            end
        end
    else
        layers = self.ldtkJson.levels[1].layerInstances
    end

    for _, layer in ipairs(layers) do
        if layer.__identifier == self.intgridLayerName then
            -- use width of map to construct a 2d array instead of a single array
            local arr2d = {}
            local cell = 1
            for _ = layer.__cHei, 1, -1 do -- n * where n == height of map
                table.insert(arr2d, {
                    unpack(layer.intGridCsv, cell, cell + layer.__cWid)
                })
                cell = cell + layer.__cWid -- increment tile number from one dimensional array position
            end
            return arr2d
        end
    end

    error("No intgrid layer found for any level")
end

function LDtkParser:findIntGrid()
    local layers
    if self.level then
        for _, level in ipairs(self.ldtkJson) do
            if level.id == self.level then
                layers = level.layerInstances
            end
        end
    else
        layers = self.ldtkJson.levels[1].layerInstances
    end

    for _, layer in ipairs(layers) do
        if layer.__identifier == self.intgridLayerName then
            -- use width of map to construct a 2d array instead of a single array
            local arr2d = {}
            local cell = 1
            for _ = layer.__cHei, 1, -1 do -- n * where n == height of map
                table.insert(arr2d, {
                    table.unpack(layer.intGridCsv, cell, cell + layer.__cWid)
                })
                cell = cell + layer.__cWid -- increment tile number from one dimensional array position
            end
            self.intGrid = arr2d
            return arr2d
        end
    end
    error("No intgrid layer found for any level")
end

function LDtkParser:readFile(path)
    local file = open(path, "rb")  -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

function LDtkParser:IntGridToWinfieldRects(intGrid)
    local grid = intGrid or self.intGrid
    -- array of arrays of int
    for gridY, row in ipairs(grid) do
        for gridX, i in ipairs(row) do
            local x = (gridX - 1) * 16
            local y = (gridY - 1) * 16
            if i == 1 then
                local terrainTile = World:newRectangleCollider(x, y, TILE_SIZE, TILE_SIZE)
                terrainTile:setType('static')
            end
        end
    end
end

return LDtkParser
