-- The 'rogue' tile set: the world as Dwarf Fortress draws it, one glyph per
-- tile on black. Same calls as src/view.lua; only what things look like
-- differs. Glyphs come from the C64 face, with a few from DejaVu Sans where
-- it has none (the zodiac crab, the fortress's smiley and shaded blocks). Its
-- ticks and dots are chunky, so the ground is mostly plain dots.
require('src.constants')
local View = require('src.view')

local Rogue = setmetatable({}, { __index = View })
Rogue.__index = Rogue

Rogue.outside = { 0, 0, 0 }

local FALLBACK_FONT = 'assets/fonts/dejavu-glyphs.ttf'
local GLYPH_SIZE = 16   -- the C64 face at 16 fits a 16 px tile
local SMALL_SIZE = 8    -- what rides along: carried goods, tools

-- Ground, by tile type. Several glyphs mean the colour seed picks one, so
-- grass is not a flat field of dots.
Rogue.GROUND = {
    grass     = { '.', '.', ',', '.' },
    dirt      = { '.', ',' },
    water     = { '~' },
    stone     = { '#' },
    snow      = { '#' },
    bridge    = { '=' },
    breakroom = { '.' },
    wall      = { 'O' },   -- a built wall, as the fortress draws one
    door      = { '+' },
}
-- How much brighter than the painted tile the glyph is, since a glyph on
-- black has far less ink than a filled square.
Rogue.GROUND_GAIN = { water = 1.35, grass = 1.15, dirt = 1.2, stone = 1.05, snow = 0.95, bridge = 1.1, breakroom = 1.05, wall = 1.1, door = 1.1 }

Rogue.GLYPH = {
    bush = '"', tree = '\226\153\163', stump = '\226\136\153',  -- U+2663 club, U+2219 bullet operator
    ore = '$', food = '%', logs = '=', gold = '$',
    floorSpot = '_', binLeft = '[', binRight = ']', bed = 'B', wall = 'O', door = '+', floor = '.', bridge = '=',
    morphi = '@', fire = '*',
    axe = '/', pickaxe = '\\', saw = '-', log = '=',
}

Rogue.FOOD_COLOR = {
    steak = { 0.85, 0.35, 0.3 }, fish = { 0.5, 0.75, 0.95 }, cheese = { 0.98, 0.85, 0.3 },
    chili = { 0.95, 0.25, 0.15 }, candy = { 0.95, 0.5, 0.8 }, grapes = { 0.6, 0.4, 0.85 },
}
-- Each species as the glyph nearest its shape, in its sprite's own body
-- colour: a dog, two round blobs (the twins are one in two colours), the
-- zodiac crab, a frog with its eyes up.
Rogue.SPECIES_GLYPH = { pupper = 'd', woofoof = 'o', twins = '8', cwab = '♋', blue = 'O', ribbit = 'm' }  -- U+264B Cancer
Rogue.SPECIES_COLOR = {
    pupper = { 0.95, 0.85, 0.6 }, woofoof = { 0.55, 0.95, 0.98 }, twins = { 1.0, 0.68, 0.78 },
    cwab = { 0.93, 0.15, 0.17 }, blue = { 0.42, 0.48, 0.95 }, ribbit = { 0.45, 0.8, 0.4 },
}

function Rogue.new(world)
    local self = View.new(world)
    setmetatable(self, Rogue)
    self.font = love.graphics.newFont(FONT_PATH, GLYPH_SIZE)
    self.font:setFilter('nearest', 'nearest')
    self.small = love.graphics.newFont(FONT_PATH, SMALL_SIZE)
    self.small:setFilter('nearest', 'nearest')
    -- what the C64 face lacks (the zodiac crab, the fortress's own glyphs)
    -- comes from a few glyphs of DejaVu Sans
    for _, pair in ipairs({ { self.font, GLYPH_SIZE }, { self.small, SMALL_SIZE } }) do
        local fb = love.graphics.newFont(FALLBACK_FONT, pair[2])
        fb:setFilter('nearest', 'nearest')
        pair[1]:setFallbacks(fb)
    end
    self.widths = {}
    return self
end

-- One glyph centred on the tile at px, py in the given colour. Keeps the
-- caller's font: the HUD draws right after the world.
function Rogue:glyph(ch, px, py, r, g, b, a, font)
    font = font or self.font
    local key = (font == self.small) and ('s' .. ch) or ch
    local w = self.widths[key]
    if not w then w = font:getWidth(ch); self.widths[key] = w end
    local size = (font == self.small) and SMALL_SIZE or GLYPH_SIZE
    local prev = love.graphics.getFont()
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, a or 1)
    love.graphics.print(ch, math.floor(px + (TILE_SIZE - w) / 2 + 0.5), math.floor(py + (TILE_SIZE - size) / 2 + 0.5))
    love.graphics.setFont(prev)
end

-- A glyph half the size, centred on a point rather than a tile.
function Rogue:smallGlyph(ch, cx, cy, r, g, b, a)
    self:glyph(ch, cx - TILE_SIZE / 2, cy - TILE_SIZE / 2, r, g, b, a, self.small)
end

function Rogue:foodColor(food)
    return self.FOOD_COLOR[food] or { 0.9, 0.8, 0.5 }
end

-- Ground ------------------------------------------------------------------

function Rogue:groundGlyph(t)
    local set = self.GROUND[t.type] or self.GROUND.grass
    return set[math.floor((t.colorSeed or 0) * #set) % #set + 1]
end

function Rogue:rebuildCanvas()
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
            local r, g, b = self:tileColor(t)
            local gain = self.GROUND_GAIN[t.type] or 1
            self:glyph(self:groundGlyph(t), px, py, math.min(1, r * gain), math.min(1, g * gain), math.min(1, b * gain))
        end
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

-- The camp: a fire in the middle that flickers, and the sign.
function Rogue:drawBreakroom()
    local br = self.world.breakroom
    if not br then return end
    local px, py = (br.x - 1) * TILE_SIZE, (br.y - 1) * TILE_SIZE
    local flick = 0.75 + 0.25 * math.sin(love.timer and love.timer.getTime() * 9 or 0)
    self:glyph(self.GLYPH.fire, px + TILE_SIZE / 2, py + TILE_SIZE / 2, 1, 0.55 * flick + 0.2, 0.1)
    local font = love.graphics.getFont()
    love.graphics.setFont(self.bubbleFont)
    local label = 'CAMP'
    local w = self.bubbleFont:getWidth(label) + 4
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle('fill', px + TILE_SIZE - w / 2, py - 11, w, 10)
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.print(label, px + TILE_SIZE - w / 2 + 2, py - 10)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 1)
end

function Rogue:drawNodes(clock)
    for _, node in ipairs(self.world.nodes) do
        local px, py = (node.x - 1) * TILE_SIZE, (node.y - 1) * TILE_SIZE
        if node.kind == NODE_BUSH then
            if node.ready then
                local c = self:foodColor(node.food)
                self:glyph(self.GLYPH.bush, px, py, c[1], c[2], c[3])
            else
                self:glyph(self.GLYPH.bush, px, py, 0.3, 0.55, 0.25)
            end
        elseif node.kind == NODE_TREE then
            if node.ready then
                self:glyph(self.GLYPH.tree, px, py, 0.25, 0.65, 0.25)
            else
                self:glyph(self.GLYPH.stump, px, py, 0.55, 0.4, 0.22)
            end
        elseif node.kind == NODE_ORE then
            local glint = 0.75 + 0.25 * math.sin((clock or 0) * 3 + node.id)
            self:glyph(self.GLYPH.ore, px, py, 0.95 * glint, 0.8 * glint, 0.2)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Buildings ---------------------------------------------------------------

function Rogue:drawFloorSpot(px, py, a)
    self:glyph(self.GLYPH.floorSpot, px, py, 0.9, 0.85, 0.65, 0.9 * a)
end

function Rogue:drawBin(px, py, a)
    self:glyph(self.GLYPH.binLeft, px, py, 0.8, 0.62, 0.36, a)
    self:glyph(self.GLYPH.binRight, px + TILE_SIZE, py, 0.8, 0.62, 0.36, a)
end

function Rogue:drawBed(px, py, a)
    self:glyph(self.GLYPH.bed, px, py, 0.93, 0.9, 0.8, a)
end

function Rogue:drawWallTile(px, py, a)
    self:glyph(self.GLYPH.wall, px, py, 0.72, 0.52, 0.28, a)
end

function Rogue:drawDoorTile(px, py, a)
    self:glyph(self.GLYPH.door, px, py, 0.95, 0.78, 0.4, a)
end

function Rogue:drawFloorTile(px, py, a)
    self:glyph(self.GLYPH.floor, px, py, 0.82, 0.7, 0.45, a)
end

function Rogue:drawBridgePlanks(px, py, a)
    self:glyph(self.GLYPH.bridge, px, py, 0.72, 0.55, 0.3, a)
end

-- Things on the ground ----------------------------------------------------

local BIN_SLOTS = { { 6, 8 }, { 12, 8 }, { 20, 8 }, { 26, 8 } }

function Rogue:drawItems(clock)
    for _, item in ipairs(self.world.items) do
        local px, py = (item.x - 1) * TILE_SIZE, (item.y - 1) * TILE_SIZE
        local tile = self.world:get(item.x, item.y)
        local inBin = tile.storage > STORAGE_FLOOR_CAPACITY
        if item.kind == ITEM_FOOD then
            local c = self:foodColor(item.food)
            if inBin then
                local q = BIN_SLOTS[((item.slot or 1) - 1) % #BIN_SLOTS + 1]
                self:smallGlyph(self.GLYPH.food, px + q[1], py + q[2], c[1], c[2], c[3])
            else
                self:glyph(self.GLYPH.food, px, py, c[1], c[2], c[3])
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Morphis -----------------------------------------------------------------

function Rogue:drawWorkerBody(w, clock, sx, feetY)
    local c = self.SPECIES_COLOR[w.sheet] or { 0.9, 0.9, 0.9 }
    if w.state == 'quitting' then c = { 0.5, 0.5, 0.5 } end
    -- a step every other frame while walking, so the glyph is seen to go
    local bob = 0
    if w.moving then bob = (math.floor((w.animTime or 0) / 0.24) % 2 == 0) and 0 or -1 end
    self:glyph(self.SPECIES_GLYPH[w.sheet] or self.GLYPH.morphi, w.x - TILE_SIZE / 2, feetY - TILE_SIZE + bob, c[1], c[2], c[3])
    local tool = w:toolInHand()
    if tool then
        local swing = 0
        if w.state == 'working' then swing = math.sin((clock or 0) * 12 + w.id) * 2 end
        self:smallGlyph(self.GLYPH[tool] or '/', w.x + 7 * sx, feetY - 9 + swing, 0.8, 0.8, 0.85)
    end
end

function Rogue:drawWorkerCargo(w, clock, sx, feetY)
    local cargo = w.slots[SLOT_WORK]
    if cargo then
        local bob = math.sin((clock or 0) * 6 + w.id) * 1
        local cy = w.y - 13 + bob
        if cargo.kind == CARGO_FOOD then
            local c = self:foodColor(cargo.food)
            self:smallGlyph(self.GLYPH.food, w.x, cy, c[1], c[2], c[3])
        elseif cargo.kind == CARGO_LOGS then
            self:smallGlyph(self.GLYPH.logs, w.x, cy, 0.75, 0.58, 0.32)
        else
            self:smallGlyph(self.GLYPH.gold, w.x, cy, 0.95, 0.8, 0.2)
        end
    end
    local pocket = w.slots[SLOT_PERSONAL]
    if pocket and pocket.kind == ITEM_FOOD then
        local c = self:foodColor(pocket.food)
        self:smallGlyph(self.GLYPH.food, w.x + 7, feetY - 3, c[1], c[2], c[3], 0.9)
    end
end

return Rogue
