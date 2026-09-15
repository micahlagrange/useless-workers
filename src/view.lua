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
    self.images = {
        side = love.graphics.newImage('assets/images/guys/whitecollarwalk.png'),
        up = love.graphics.newImage('assets/images/guys/upwalk.png'),
        down = love.graphics.newImage('assets/images/guys/downwalk.png'),
    }
    self.frames = {}
    for name, img in pairs(self.images) do
        local grid = anim8.newGrid(16, 16, img:getWidth(), img:getHeight())
        self.frames[name] = grid('1-4', 1)
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
    -- table
    love.graphics.setColor(0.55, 0.42, 0.25)
    love.graphics.rectangle('fill', px + 6, py + 20, 20, 8)
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

function View:drawTrees(clock)
    for _, tree in ipairs(self.world.trees) do
        local px, py = (tree.x - 1) * TILE_SIZE, (tree.y - 1) * TILE_SIZE
        love.graphics.setColor(0.42, 0.3, 0.16)
        love.graphics.rectangle('fill', px + 6, py + 9, 4, 6)
        if tree.ripe then
            love.graphics.setColor(0.3, 0.56, 0.24)
        else
            love.graphics.setColor(0.25, 0.4, 0.2)
        end
        love.graphics.circle('fill', px + 8, py + 7, 6)
        love.graphics.setColor(0.2, 0.32, 0.15)
        love.graphics.circle('line', px + 8, py + 7, 6)
        if tree.ripe then
            local img = self:fruitImage(tree.fruit or 1)
            if img then
                local bob = math.sin((clock or 0) * 4 + tree.id) * 1
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, px + 8, py + bob, 0, 0.6, 0.6, 8, 8)
            end
        elseif tree.memo then
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
    local frameIndex = 1
    if w.moving then
        frameIndex = math.floor(w.animTime / FRAME_TIME) % 4 + 1
    end
    local sheet, quads, sx = self.images.side, self.frames.side, 1
    if w.facing == 'right' then
        sx = -1
    elseif w.facing == 'up' then
        sheet, quads = self.images.up, self.frames.up
    elseif w.facing == 'down' then
        sheet, quads = self.images.down, self.frames.down
    end
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
        love.graphics.setColor(w.tint[1], w.tint[2], w.tint[3], 1)
    end
    love.graphics.draw(sheet, quads[frameIndex], w.x, feetY, 0, sx, 1, 8, 16)
    if w.carrying then
        local img = self:fruitImage(w.carrying)
        if img then
            local bob = math.sin((clock or 0) * 6 + w.id) * 1
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, w.x, w.y - 15 + bob, 0, 0.7, 0.7, 8, 8)
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
