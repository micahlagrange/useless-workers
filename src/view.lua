-- Everything drawn in world space: tiles, break room, trees, workers.
require('src.constants')
local Util = require('src.util')
local anim8 = require('libs.anim8')

local View = {}
View.__index = View

local FRAME_TIME = 0.12

function View.new(world)
    local self = setmetatable({}, View)
    self.world = world
    self.canvas = love.graphics.newCanvas(world.w * TILE_SIZE, world.h * TILE_SIZE)
    self.canvas:setFilter('nearest', 'nearest')
    self.canvasVersion = -1
    -- one sheet per morphi species, all 16 px frames facing right
    self.sheets = {}
    for key, _ in pairs(MORPHI_SHEET_NAMES) do
        local img = love.graphics.newImage('assets/images/morphis/' .. key .. '-worker-walk.png')
        local frames = math.floor(img:getWidth() / 16)
        local grid = anim8.newGrid(16, 16, img:getWidth(), img:getHeight())
        self.sheets[key] = { image = img, quads = grid('1-' .. frames, 1), frames = frames }
    end
    self.fruitImages = {}
    local files = love.filesystem.getDirectoryItems('assets/images/fruit')
    table.sort(files)
    for _, file in ipairs(files) do
        if file:match('^yp_.*%.png$') then
            self.fruitImages[#self.fruitImages + 1] = love.graphics.newImage('assets/images/fruit/' .. file)
        end
    end
    self.bubbleFont = love.graphics.newFont('assets/fonts/commodore64.ttf', 8)
    self.rgb = {}
    return self
end

function View:fruitImage(index)
    if #self.fruitImages == 0 then return nil end
    return self.fruitImages[(index - 1) % #self.fruitImages + 1]
end

function View:hex(h)
    if not self.rgb[h] then self.rgb[h] = Util.hexToRgb(h) end
    return self.rgb[h]
end

local function band(v, lo, hi)
    if hi - lo <= 0 then return 1 end
    return Util.clamp((v - lo) / (hi - lo), 0, 1)
end

function View:tileColor(t)
    local pal = TILE_PALETTE[t.type] or GRASS_COLORS
    local base = self:hex(pal[math.floor(t.colorSeed * #pal) % #pal + 1])
    local bands = self.world.bands
    local f = 1
    if t.type == TILE_WATER then
        f = 0.7 + 0.35 * band(t.altitude, 0, bands.water)
    elseif t.type == TILE_GRASS or t.type == TILE_DIRT then
        f = 0.86 + 0.24 * band(t.altitude, bands.water, bands.grass)
    elseif t.type == TILE_STONE then
        f = 0.8 + 0.4 * band(t.altitude, bands.grass, bands.stone)
    end
    return base[1] * f, base[2] * f, base[3] * f
end

-- Must run outside the camera transform: the tiles are baked into the canvas
-- in world pixels, so any active scale or translate would be baked in too.
function View:rebuildCanvas()
    if self.canvasVersion == self.world.version then return end
    self.canvasVersion = self.world.version
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 1)
    for x = 1, self.world.w do
        for y = 1, self.world.h do
            local t = self.world.tiles[x][y]
            local px, py = (x - 1) * TILE_SIZE, (y - 1) * TILE_SIZE
            love.graphics.setColor(self:tileColor(t))
            love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
            if t.type == TILE_BRIDGE then
                love.graphics.setColor(0.35, 0.26, 0.14)
                love.graphics.rectangle('fill', px, py + 3, TILE_SIZE, 1)
                love.graphics.rectangle('fill', px, py + 8, TILE_SIZE, 1)
                love.graphics.rectangle('fill', px, py + 13, TILE_SIZE, 1)
            elseif t.type == TILE_STONE then
                love.graphics.setColor(0, 0, 0, 0.18)
                love.graphics.rectangle('fill', px + 3, py + 4, 5, 2)
                love.graphics.rectangle('fill', px + 9, py + 10, 4, 2)
            elseif t.type == TILE_BREAKROOM then
                love.graphics.setColor(0.35, 0.28, 0.16)
                love.graphics.rectangle('line', px + 0.5, py + 0.5, TILE_SIZE - 1, TILE_SIZE - 1)
            end
        end
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawWorld()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
end

function View:drawBreakroom()
    local br = self.world.breakroom
    if not br then return end
    local px, py = (br.x - 1) * TILE_SIZE, (br.y - 1) * TILE_SIZE
    -- water cooler
    love.graphics.setColor(0.45, 0.7, 0.9)
    love.graphics.rectangle('fill', px + 4, py + 3, 5, 8)
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.rectangle('fill', px + 3, py + 11, 7, 3)
    -- coffee maker
    love.graphics.setColor(0.25, 0.2, 0.18)
    love.graphics.rectangle('fill', px + 20, py + 5, 8, 9)
    love.graphics.setColor(0.9, 0.5, 0.3)
    love.graphics.rectangle('fill', px + 22, py + 7, 4, 2)
    -- table with the pantry stock on it
    love.graphics.setColor(0.55, 0.42, 0.25)
    love.graphics.rectangle('fill', px + 6, py + 20, 20, 8)
    local stock = math.min(br.food or 0, 5)
    for i = 1, stock do
        local img = self:fruitImage(i * 37)
        if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, px + 6 + i * 3, py + 22, 0, 0.4, 0.4, 8, 8)
        end
    end
    if (br.food or 0) > 5 then
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- sign
    local font = love.graphics.getFont()
    love.graphics.setFont(self.bubbleFont)
    local label = 'BREAK ROOM'
    local w = self.bubbleFont:getWidth(label) + 4
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle('fill', px + TILE_SIZE - w / 2, py - 11, w, 10)
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.print(label, px + TILE_SIZE - w / 2 + 2, py - 10)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawNodes(clock)
    for _, node in ipairs(self.world.nodes) do
        local px, py = (node.x - 1) * TILE_SIZE, (node.y - 1) * TILE_SIZE
        if node.kind == NODE_BUSH then
            love.graphics.setColor(0.27, 0.48, 0.22)
            love.graphics.ellipse('fill', px + 8, py + 11, 7, 4.5)
            love.graphics.setColor(0.36, 0.6, 0.28)
            love.graphics.ellipse('fill', px + 6, py + 9, 4, 3.5)
            love.graphics.ellipse('fill', px + 10, py + 10, 4, 3)
            if node.ready then
                local img = self:fruitImage(node.fruit or 1)
                if img then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(img, px + 8, py + 7, 0, 0.5, 0.5, 8, 8)
                end
            end
        elseif node.kind == NODE_TREE then
            if node.ready then
                love.graphics.setColor(0.42, 0.3, 0.16)
                love.graphics.rectangle('fill', px + 6, py + 8, 4, 8)
                love.graphics.setColor(0.24, 0.45, 0.2)
                love.graphics.circle('fill', px + 8, py + 5, 7)
                love.graphics.setColor(0.32, 0.56, 0.26)
                love.graphics.circle('fill', px + 6, py + 3, 4)
                love.graphics.setColor(0.18, 0.32, 0.14)
                love.graphics.circle('line', px + 8, py + 5, 7)
            else
                -- stump
                love.graphics.setColor(0.45, 0.32, 0.18)
                love.graphics.rectangle('fill', px + 5, py + 9, 6, 5)
                love.graphics.setColor(0.7, 0.55, 0.32)
                love.graphics.ellipse('fill', px + 8, py + 9, 3.5, 2)
                love.graphics.setColor(0.45, 0.32, 0.18)
                love.graphics.ellipse('line', px + 8, py + 9, 2, 1)
            end
        elseif node.kind == NODE_ORE then
            local glint = 0.75 + 0.25 * math.sin((clock or 0) * 3 + node.id)
            love.graphics.setColor(0.95 * glint, 0.8 * glint, 0.2)
            love.graphics.rectangle('fill', px + 3, py + 4, 3, 3)
            love.graphics.rectangle('fill', px + 9, py + 7, 4, 3)
            love.graphics.rectangle('fill', px + 5, py + 11, 3, 2)
            love.graphics.setColor(1, 0.95, 0.6)
            love.graphics.rectangle('fill', px + 10, py + 7, 1, 1)
            love.graphics.rectangle('fill', px + 4, py + 4, 1, 1)
        end
        if node.memo and not node.ready then
            love.graphics.setColor(1, 0.95, 0.5)
            love.graphics.rectangle('fill', px + 11, py + 1, 4, 4)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawTileOutline(tx, ty, color, size)
    size = size or 1
    local px, py = (tx - 1) * TILE_SIZE, (ty - 1) * TILE_SIZE
    love.graphics.setColor(color)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle('line', px + 0.5, py + 0.5, TILE_SIZE * size - 1, TILE_SIZE * size - 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawTileFill(tx, ty, color)
    local px, py = (tx - 1) * TILE_SIZE, (ty - 1) * TILE_SIZE
    love.graphics.setColor(color)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawBubble(x, y, text, color)
    local font = love.graphics.getFont()
    love.graphics.setFont(self.bubbleFont)
    local w = self.bubbleFont:getWidth(text) + 4
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle('fill', x - w / 2, y, w, 10)
    love.graphics.setColor(color or { 0.85, 0.2, 0.15 })
    love.graphics.print(text, x - w / 2 + 2, y + 1)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawWorker(w, clock, selected)
    local sheet = self.sheets[w.sheet] or self.sheets.pupper
    local frameIndex = 1
    if w.moving then
        frameIndex = math.floor(w.animTime / FRAME_TIME) % sheet.frames + 1
    end
    local sx = (w.facing == 'left') and -1 or 1
    local feetY = w.y + 4
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse('fill', w.x, feetY, 6, 2.5)
    if selected then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.ellipse('line', w.x, feetY, 8, 4)
    end
    if w.state == 'quitting' then
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(sheet.image, sheet.quads[frameIndex], w.x, feetY, 0, sx, 1, 8, 16)
    if w.carrying then
        local bob = math.sin((clock or 0) * 6 + w.id) * 1
        local cy = w.y - 15 + bob
        if w.carrying == CARGO_FOOD then
            local img = self:fruitImage(w.carryingFruit or 1)
            if img then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, w.x, cy, 0, 0.7, 0.7, 8, 8)
            end
        elseif w.carrying == CARGO_LOGS then
            love.graphics.setColor(0.5, 0.35, 0.18)
            love.graphics.rectangle('fill', w.x - 6, cy - 2, 12, 4)
            love.graphics.setColor(0.75, 0.58, 0.32)
            love.graphics.rectangle('fill', w.x + 4, cy - 2, 2, 4)
        else
            love.graphics.setColor(0.95, 0.8, 0.2)
            love.graphics.rectangle('fill', w.x - 3, cy - 3, 6, 5)
            love.graphics.setColor(1, 0.95, 0.6)
            love.graphics.rectangle('fill', w.x - 2, cy - 2, 2, 1)
        end
    end
    if w:isWorking() and w.hunger < 40 then
        local width = 12 * (w.hunger / HUNGER_MAX)
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle('fill', w.x - 6, feetY + 3, 12, 2)
        love.graphics.setColor(0.9, 0.25, 0.2)
        love.graphics.rectangle('fill', w.x - 6, feetY + 3, width, 2)
    end
    if w.bubble then
        self:drawBubble(w.x, w.y - 26, w.bubble.text)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawWorkers(workers, clock, selectedWorker)
    local sorted = {}
    for _, w in ipairs(workers) do
        if w.alive then sorted[#sorted + 1] = w end
    end
    table.sort(sorted, function(a, b) return a.y < b.y end)
    for _, w in ipairs(sorted) do
        self:drawWorker(w, clock, w == selectedWorker)
    end
end

return View
