-- Everything drawn in world space: tiles, break room, trees, workers.
require('src.constants')
local Util = require('src.util')
local anim8 = require('libs.anim8')

local View = {}
View.__index = View

local FRAME_TIME = 0.12

-- The ground beyond the map's edge.
View.outside = { 0.11, 0.13, 0.09 }

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
    self.foodImages = {}
    for food, file in pairs(FOOD_SPRITE) do
        self.foodImages[food] = love.graphics.newImage('assets/images/fruit/' .. file)
    end
    self.bubbleFont = love.graphics.newFont(FONT_PATH, 8)
    self.bubbleFont:setFilter('linear', 'linear')
    self.rgb = {}
    return self
end

function View:foodImage(food)
    return self.foodImages[food] or self.foodImages[FOOD_KINDS[1]]
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
                -- a lit top edge and a shadowed foot, so stone reads as raised rock
                love.graphics.setColor(1, 1, 1, 0.14)
                love.graphics.rectangle('fill', px, py, TILE_SIZE, 1)
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.rectangle('fill', px, py + TILE_SIZE - 2, TILE_SIZE, 2)
                love.graphics.setColor(0, 0, 0, 0.22)
                love.graphics.rectangle('fill', px + 3, py + 4, 5, 2)
                love.graphics.rectangle('fill', px + 9, py + 10, 4, 2)
            elseif t.type == TILE_BREAKROOM then
                love.graphics.setColor(0.35, 0.28, 0.16)
                love.graphics.rectangle('line', px + 0.5, py + 0.5, TILE_SIZE - 1, TILE_SIZE - 1)
            elseif t.type == TILE_WALL then
                self:drawWallTile(px, py, 1)
            elseif t.type == TILE_DOOR then
                self:drawDoorTile(px, py, 1)
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
    -- the home nest: where the bunch settled (look only; the decision log's
    -- settlement marker). A 3x3 marker of soft corners round the 2x2 camp
    -- ground, and one big woven nest in the middle of it.
    local T = TILE_SIZE
    local mx, my, ms = px - T / 2, py - T / 2, 3 * T
    love.graphics.setColor(1, 0.95, 0.75, 0.75)
    love.graphics.setLineWidth(1.5)
    local c = 6
    for _, k in ipairs({ { 0, 0, 1, 1 }, { 1, 0, -1, 1 }, { 0, 1, 1, -1 }, { 1, 1, -1, -1 } }) do
        local x0, y0 = mx + k[1] * ms, my + k[2] * ms
        love.graphics.line(x0 + k[3] * c, y0, x0, y0, x0, y0 + k[4] * c)
    end
    local cx, cy = px + T, py + T
    -- the nest: a ring of woven twigs round a soft middle
    love.graphics.setColor(0.6, 0.45, 0.28)
    love.graphics.ellipse('fill', cx, cy + 2, T * 0.82, T * 0.5)
    love.graphics.setColor(0.93, 0.85, 0.62)
    love.graphics.ellipse('fill', cx, cy + 1, T * 0.6, T * 0.32)
    love.graphics.setColor(0.72, 0.55, 0.34)
    for i = 0, 9 do
        local a = i / 10 * math.pi * 2
        love.graphics.line(cx + math.cos(a) * T * 0.62, cy + 2 + math.sin(a) * T * 0.38,
            cx + math.cos(a + 0.5) * T * 0.8, cy + 2 + math.sin(a + 0.5) * T * 0.48)
    end
    love.graphics.setLineWidth(1)
    -- sign
    local font = love.graphics.getFont()
    love.graphics.setFont(self.bubbleFont)
    local label = 'HOME'
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
                local img = self:foodImage(node.food)
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
                -- shaken bare: the tree stays, its twigs grow back
                love.graphics.setColor(0.42, 0.3, 0.16)
                love.graphics.rectangle('fill', px + 7, py + 6, 2, 10)
                love.graphics.line(px + 8, py + 8, px + 4, py + 3)
                love.graphics.line(px + 8, py + 7, px + 12, py + 2)
                love.graphics.line(px + 8, py + 10, px + 12, py + 7)
                love.graphics.setColor(0.32, 0.56, 0.26, 0.6)
                love.graphics.circle('fill', px + 4, py + 3, 1.5)
                love.graphics.circle('fill', px + 12, py + 2, 1.5)
            end
        elseif node.kind == NODE_GRASS then
            local h = node.ready and 7 or 2
            love.graphics.setColor(0.36, 0.62, 0.3)
            for i = 0, 4 do
                local gx = px + 4 + i * 2
                love.graphics.line(gx, py + 13, gx + (i - 2) * 0.8, py + 13 - h - (i % 2) * 2)
            end
        elseif node.kind == NODE_CRITTER then
            -- a little round critter with long ears, bobbing
            local hop = math.abs(math.sin((clock or 0) * 5 + node.id)) * 1.5
            love.graphics.setColor(0, 0, 0, 0.18)
            love.graphics.ellipse('fill', px + 8, py + 13, 4, 1.5)
            love.graphics.setColor(0.93, 0.88, 0.8)
            love.graphics.ellipse('fill', px + 8, py + 10 - hop, 4, 3)
            love.graphics.ellipse('fill', px + 6.5, py + 6 - hop, 1, 2.5)
            love.graphics.ellipse('fill', px + 9.5, py + 6 - hop, 1, 2.5)
            love.graphics.setColor(0.2, 0.15, 0.15)
            love.graphics.rectangle('fill', px + 9, py + 9 - hop, 1, 1)
        elseif node.kind == NODE_LEAVES then
            for i, c in ipairs({ { 6, 10, 0.86, 0.55, 0.3 }, { 10, 11, 0.93, 0.72, 0.32 }, { 8, 8, 0.78, 0.42, 0.25 } }) do
                love.graphics.setColor(c[3], c[4], c[5])
                love.graphics.ellipse('fill', px + c[1], py + c[2], 3, 1.8)
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
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Built storage tiles: a wooden pallet on the ground.
-- Buildings, drawn top down. Each takes an alpha so a designation can be
-- shown as a faded ghost of what it will become.

-- Floor storage: a chalked square on the ground.
function View:drawFloorSpot(px, py, a)
    -- a stash: a big soft leaf laid flat, with its vein
    love.graphics.setColor(0, 0, 0, 0.15 * a)
    love.graphics.ellipse('fill', px + 8.5, py + 9, 6.5, 5.5)
    love.graphics.setColor(0.55, 0.8, 0.45, 0.9 * a)
    love.graphics.ellipse('fill', px + 8, py + 8, 6.5, 5.5)
    love.graphics.setColor(0.4, 0.65, 0.33, 0.9 * a)
    love.graphics.line(px + 2.5, py + 9.5, px + 13.5, py + 6.5)
end

-- A bin seen from above: a wooden frame with a dark open inside, lit from
-- the top left. Items sit in the four quadrants of the opening.
-- A bin, top down, two tiles wide from (px, py).
function View:drawBin(px, py, a)
    -- a basket of woven grass, two tiles wide; things sit in its four
    -- quarters, so the open middle keeps the bin's shape
    local w = 2 * TILE_SIZE - 2
    love.graphics.setColor(0, 0, 0, 0.18 * a)
    love.graphics.rectangle('fill', px + 2, py + 2, w, 14, 4, 4)
    love.graphics.setColor(0.86, 0.72, 0.45, a)
    love.graphics.rectangle('fill', px + 1, py + 1, w, 14, 4, 4)
    love.graphics.setColor(0.55, 0.4, 0.22, a)
    love.graphics.rectangle('fill', px + 3, py + 3, w - 4, 10, 3, 3)
    -- the weave round the rim
    love.graphics.setColor(0.72, 0.56, 0.32, a)
    for i = 0, math.floor(w / 3) do
        love.graphics.rectangle('fill', px + 2 + i * 3, py + 1, 1, 2)
        love.graphics.rectangle('fill', px + 2 + i * 3, py + 13, 1, 2)
    end
end

-- What a tool will build, drawn faint where it will go; red where it cannot.
function View:drawGhost(kind, tx, ty, ok)
    local px, py = (tx - 1) * TILE_SIZE, (ty - 1) * TILE_SIZE
    local a = ok and 0.65 or 0.35
    if kind == SITE_BIN then self:drawBin(px, py, a)
    elseif kind == SITE_BED then self:drawBed(px, py, a)
    elseif kind == SITE_DOOR then self:drawDoorTile(px, py, a)
    elseif kind == SITE_WALL then self:drawWallTile(px, py, a)
    elseif kind == SITE_STORAGE then self:drawFloorSpot(px, py, a)
    end
    local w = kind == SITE_BIN and 2 or 1
    love.graphics.setColor(ok and 1 or 1, ok and 1 or 0.3, ok and 1 or 0.25, ok and 0.9 or 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle('line', px + 0.5, py + 0.5, TILE_SIZE * w - 1, TILE_SIZE - 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawBed(px, py, a)
    -- a nest: a ring of twigs round a soft, downy middle
    love.graphics.setColor(0, 0, 0, 0.15 * a)
    love.graphics.ellipse('fill', px + 8.5, py + 10, 7, 4.5)
    love.graphics.setColor(0.6, 0.45, 0.28, a)
    love.graphics.ellipse('fill', px + 8, py + 9, 7, 4.5)
    love.graphics.setColor(0.95, 0.88, 0.68, a)
    love.graphics.ellipse('fill', px + 8, py + 8.5, 4.5, 2.6)
    love.graphics.setColor(0.72, 0.55, 0.34, a)
    love.graphics.line(px + 2, py + 9, px + 6, py + 12)
    love.graphics.line(px + 10, py + 12, px + 14, py + 9)
    love.graphics.line(px + 4, py + 6, px + 8, py + 5)
end

-- A wall from above: dark timber courses with the mortar showing, lit
-- along the top edge so it reads as standing up.
function View:drawWallTile(px, py, a)
    love.graphics.setColor(0.42, 0.31, 0.16, a)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
    love.graphics.setColor(0.24, 0.17, 0.08, a)
    love.graphics.rectangle('fill', px, py + 5, TILE_SIZE, 1)
    love.graphics.rectangle('fill', px, py + 10, TILE_SIZE, 1)
    love.graphics.rectangle('fill', px, py + 15, TILE_SIZE, 1)
    love.graphics.rectangle('fill', px + 8, py, 1, 5)
    love.graphics.rectangle('fill', px + 4, py + 6, 1, 4)
    love.graphics.rectangle('fill', px + 12, py + 6, 1, 4)
    love.graphics.rectangle('fill', px + 8, py + 11, 1, 4)
    love.graphics.setColor(0.6, 0.46, 0.26, a)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, 1)
end

-- A door: a light plank in a dark frame, knob on the right.
function View:drawDoorTile(px, py, a)
    love.graphics.setColor(0.24, 0.17, 0.08, a)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
    love.graphics.setColor(0.72, 0.56, 0.3, a)
    love.graphics.rectangle('fill', px + 2, py + 2, 12, 12)
    love.graphics.setColor(0.55, 0.42, 0.22, a)
    love.graphics.rectangle('fill', px + 8, py + 2, 1, 12)
    love.graphics.setColor(0.95, 0.85, 0.4, a)
    love.graphics.rectangle('fill', px + 11, py + 7, 2, 2)
end

-- Arcade living space: a rug of pale planks with a stitched border.
function View:drawFloorTile(px, py, a)
    love.graphics.setColor(0.78, 0.66, 0.42, a)
    love.graphics.rectangle('fill', px + 1, py + 1, 14, 14)
    love.graphics.setColor(0.66, 0.54, 0.32, a)
    love.graphics.rectangle('fill', px + 1, py + 5, 14, 1)
    love.graphics.rectangle('fill', px + 1, py + 10, 14, 1)
    love.graphics.setColor(0.5, 0.38, 0.2, 0.9 * a)
    love.graphics.rectangle('line', px + 1.5, py + 1.5, 13, 13)
end

function View:drawBridgePlanks(px, py, a)
    love.graphics.setColor(0.62, 0.47, 0.27, a)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
    love.graphics.setColor(0.35, 0.26, 0.14, a)
    love.graphics.rectangle('fill', px, py + 3, TILE_SIZE, 1)
    love.graphics.rectangle('fill', px, py + 8, TILE_SIZE, 1)
    love.graphics.rectangle('fill', px, py + 13, TILE_SIZE, 1)
end

function View:drawStorage()
    for _, st in ipairs(self.world:storageTiles()) do
        local px, py = (st.x - 1) * TILE_SIZE, (st.y - 1) * TILE_SIZE
        if st.capacity <= STORAGE_FLOOR_CAPACITY then
            self:drawFloorSpot(px, py, 1)
        else
            self:drawBin(px, py, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawFloors()
    for _, f in ipairs(self.world.floors) do
        self:drawFloorTile((f.x - 1) * TILE_SIZE, (f.y - 1) * TILE_SIZE, 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function View:drawBeds()
    for _, b in ipairs(self.world.beds) do
        self:drawBed((b.x - 1) * TILE_SIZE, (b.y - 1) * TILE_SIZE, 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Designations. Mine marks are an orange X; every building shows as a
-- faded ghost of what it will be, a little brighter once someone is on it.
function View:drawSites(clock)
    local pulse = 0.55 + 0.25 * math.sin((clock or 0) * 4)
    love.graphics.setLineWidth(1)
    for _, site in ipairs(self.world.sites) do
        local px, py = (site.x - 1) * TILE_SIZE, (site.y - 1) * TILE_SIZE
        if site.kind == SITE_MINE then
            love.graphics.setColor(1, 0.6, 0.2, site.claimedBy and 0.9 or pulse)
            love.graphics.rectangle('line', px + 1.5, py + 1.5, TILE_SIZE - 3, TILE_SIZE - 3)
            love.graphics.line(px + 4, py + 4, px + 12, py + 12)
            love.graphics.line(px + 12, py + 4, px + 4, py + 12)
        else
            local a = site.claimedBy and 0.7 or (0.3 + 0.15 * pulse)
            if site.kind == SITE_STORAGE then
                if self.world.arcade then self:drawFloorTile(px, py, a) else self:drawFloorSpot(px, py, a) end
            elseif site.kind == SITE_BIN then self:drawBin(px, py, a)
            elseif site.kind == SITE_BED then self:drawBed(px, py, a)
            elseif site.kind == SITE_WALL then self:drawWallTile(px, py, a)
            elseif site.kind == SITE_DOOR then self:drawDoorTile(px, py, a)
            elseif site.kind == SITE_BRIDGE then self:drawBridgePlanks(px, py, a)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Quadrant offsets inside a bin, in the order items were stored.
local BIN_SLOTS = { { 6, 8 }, { 12, 8 }, { 20, 8 }, { 26, 8 } }

function View:drawItems(clock)
    for _, item in ipairs(self.world.items) do
        local px, py = (item.x - 1) * TILE_SIZE, (item.y - 1) * TILE_SIZE
        local tile = self.world:get(item.x, item.y)
        local inBin = tile.storage > STORAGE_FLOOR_CAPACITY
        if not inBin then
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.ellipse('fill', px + 8, py + 12, 5, 2)
        end
        if item.kind == ITEM_FOOD then
            local img = self:foodImage(item.food)
            if img then
                love.graphics.setColor(1, 1, 1, 1)
                if inBin then
                    local q = BIN_SLOTS[((item.slot or 1) - 1) % #BIN_SLOTS + 1]
                    love.graphics.draw(img, px + q[1], py + q[2], 0, 0.36, 0.36, 8, 8)
                else
                    love.graphics.draw(img, px + 8, py + 8, 0, 0.6, 0.6, 8, 8)
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The spot being looked at: brackets at the corners that breathe, and a
-- soft fill, so it stands out from the alert outlines.
function View:drawFocus(tx, ty, clock)
    local px, py = (tx - 1) * TILE_SIZE, (ty - 1) * TILE_SIZE
    local g = 2 + math.sin((clock or 0) * 5) * 1.5
    love.graphics.setColor(1, 0.9, 0.3, 0.22)
    love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.setLineWidth(1.5)
    local s, L = TILE_SIZE, 5
    local x0, y0, x1, y1 = px - g, py - g, px + s + g, py + s + g
    love.graphics.line(x0, y0 + L, x0, y0, x0 + L, y0)
    love.graphics.line(x1 - L, y0, x1, y0, x1, y0 + L)
    love.graphics.line(x0, y1 - L, x0, y1, x0 + L, y1)
    love.graphics.line(x1 - L, y1, x1, y1, x1, y1 - L)
    love.graphics.setLineWidth(1)
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

-- Hand tools, drawn about the grip so they can swing. Facing right.
function View:drawTool(kind, x, y, angle, sx)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(sx, 1)
    love.graphics.rotate(angle)
    if kind == 'twigs' then
        -- a little bundle of sticks, tied with a grass bow
        love.graphics.setColor(0.62, 0.45, 0.28)
        love.graphics.line(-4, -1, 5, -4)
        love.graphics.line(-4, 0, 5, -1)
        love.graphics.line(-3, 2, 5, 1)
        love.graphics.setColor(0.55, 0.78, 0.45)
        love.graphics.rectangle('fill', 0, -3, 2, 4)
    elseif kind == 'spade' then
        -- a tiny round spade
        love.graphics.setColor(0.62, 0.45, 0.28)
        love.graphics.rectangle('fill', -1, -7, 2, 7)
        love.graphics.setColor(0.86, 0.82, 0.74)
        love.graphics.ellipse('fill', 0, 1, 3, 3.5)
    elseif kind == 'leaf' then
        -- a big leaf for weaving a nest
        love.graphics.setColor(0.5, 0.78, 0.42)
        love.graphics.ellipse('fill', 2, -3, 4, 2.2)
        love.graphics.setColor(0.36, 0.6, 0.3)
        love.graphics.line(-2, -3, 6, -3)
    end
    love.graphics.pop()
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
    self:drawWorkerBody(w, clock, sx, feetY)
    self:drawWorkerCargo(w, clock, sx, feetY)
    if w.state == 'breaking' then
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print('z', w.x + 6, w.y - 14)
    end
    -- arcade: a tick once the meal is had, nothing before
    if w.arcade then
        if w.ate then
            love.graphics.setColor(0.45, 0.85, 0.4, 0.95)
            love.graphics.setLineWidth(1)
            love.graphics.line(w.x - 5, feetY + 4, w.x - 2, feetY + 6.5, w.x + 4, feetY + 1.5)
        end
    -- hunger as a dot in its status colour: blue satiated, green fed, amber
    -- hungry, red (blinking) starving
    elseif w:isWorking() or w.stage == 'baby' then
        local status = w:hungerStatus()
        local col = ({ satiated = { 0.5, 0.75, 1.0 }, fed = { 0.45, 0.8, 0.4 }, hungry = { 0.95, 0.72, 0.25 }, starving = { 0.95, 0.25, 0.2 } })[status]
        if status ~= 'starving' or math.floor(clock * 3) % 2 == 0 then
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.circle('fill', w.x, feetY + 4, 2.2)
            love.graphics.setColor(col[1], col[2], col[3], 1)
            love.graphics.circle('fill', w.x, feetY + 4, 1.6)
        end
    end
    if w.bubble then
        self:drawBubble(w.x, w.y - 26, w.bubble.text)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The morphi itself, feet at feetY, facing sx (1 right, -1 left), and the
-- tool in its hand. A tile set with another look overrides this.
function View:drawWorkerBody(w, clock, sx, feetY)
    local sheet = self.sheets[w.sheet] or self.sheets.pupper
    local frameIndex = 1
    if w.moving then
        frameIndex = math.floor(w.animTime / FRAME_TIME) % sheet.frames + 1
    end
    if w.state == 'quitting' then
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- standing about, a little blob breathes: a soft squash and stretch
    local sy = 1
    if not w.moving then sy = 1 + 0.06 * math.sin((clock or 0) * 4 + w.id * 1.7) end
    if w.stage == 'egg' then
        -- a speckled egg, wobbling now and then
        local wob = math.sin((clock or 0) * 9 + w.id) * (math.floor((clock or 0) + w.id) % 4 == 0 and 0.25 or 0)
        love.graphics.push()
        love.graphics.translate(w.x, feetY - 5)
        love.graphics.rotate(wob)
        love.graphics.setColor(0.98, 0.95, 0.86)
        love.graphics.ellipse('fill', 0, 0, 4, 5)
        love.graphics.setColor(0.72, 0.6, 0.5)
        love.graphics.circle('fill', -1.5, -1, 0.7)
        love.graphics.circle('fill', 1.2, 1.5, 0.6)
        love.graphics.circle('fill', 1, -2.5, 0.5)
        love.graphics.pop()
        return
    end
    local size = w.stage == 'baby' and BABY_SCALE or 1
    love.graphics.draw(sheet.image, sheet.quads[frameIndex], w.x, feetY, 0, sx * (2 - sy) * size, sy * size, 8, 16)
    local tool = w:toolInHand()
    if tool then
        local swing = 0
        if w.state == 'working' then swing = -0.9 + 0.7 * math.sin((clock or 0) * 12 + w.id) end
        self:drawTool(tool, w.x + 5 * sx, feetY - 6, swing, sx)
    end
end

-- What it carries: the work load bobbing overhead, the pocketed snack at
-- its side.
function View:drawWorkerCargo(w, clock, sx, feetY)
    local cargo = w.slots[SLOT_WORK]
    if cargo then
        local bob = math.sin((clock or 0) * 6 + w.id) * 1
        local cy = w.y - 15 + bob
        if cargo.kind == CARGO_FOOD then
            local img = self:foodImage(cargo.food)
            if img then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, w.x, cy, 0, 0.7, 0.7, 8, 8)
            end
        elseif cargo.kind == CARGO_LOGS then
            love.graphics.setColor(0.62, 0.45, 0.28)
            love.graphics.line(w.x - 5, cy + 1, w.x + 5, cy - 2)
            love.graphics.line(w.x - 5, cy - 1, w.x + 5, cy + 1)
        elseif cargo.kind == CARGO_GRASS then
            love.graphics.setColor(0.42, 0.7, 0.34)
            for i = -2, 2 do love.graphics.line(w.x + i, cy + 2, w.x + i * 2, cy - 3) end
        elseif cargo.kind == CARGO_LEAVES then
            love.graphics.setColor(0.9, 0.62, 0.3)
            love.graphics.ellipse('fill', w.x - 2, cy, 3, 1.8)
            love.graphics.setColor(0.8, 0.45, 0.25)
            love.graphics.ellipse('fill', w.x + 2, cy - 1, 3, 1.8)
        else
            love.graphics.setColor(0.95, 0.8, 0.2)
            love.graphics.rectangle('fill', w.x - 3, cy - 3, 6, 5)
            love.graphics.setColor(1, 0.95, 0.6)
            love.graphics.rectangle('fill', w.x - 2, cy - 2, 2, 1)
        end
    end
    local pocket = w.slots[SLOT_PERSONAL]
    if pocket and pocket.kind == ITEM_FOOD then
        local img = self:foodImage(pocket.food)
        if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, w.x + 7, feetY - 4, 0, 0.4, 0.4, 8, 8)
        end
    end
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
