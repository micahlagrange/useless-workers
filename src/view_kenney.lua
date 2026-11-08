-- The two Kenney tile sets (CC0, https://kenney.nl): the same world drawn
-- from his art instead of shapes.
--   'pixel': Tiny Town, Tiny Farm, Tiny Dungeon and the Pixel Platformer food
--            pack, 16 px tiles drawn with nearest filtering.
--   'soft':  RPG Tiles Vector and the round Animal Pack, smooth art, drawn
--            with linear filtering. The ground is baked at twice the
--            world's resolution so it stays crisp when the camera zooms.
-- Same calls as src/view.lua; only what things look like differs. Pictures
-- Kenney has none for (water in the pixel set, the gold, the bits
-- of the soft set) keep the painted look. Each skin is one tileset,
-- assets/images/kenney/<skin>.png; src/kenney_atlas.lua says where each
-- picture sits in it.
require('src.constants')
local View = require('src.view')
local ATLAS = require('src.kenney_atlas')
local Feel = require('src.feel')

local Kenney = setmetatable({}, { __index = View })
Kenney.__index = Kenney

local DIR = 'assets/images/kenney/'

Kenney.SKINS = {
    pixel = {
        filter = 'nearest', bake = 1,
        ground = {
            grass = { 'grass1', 'grass2', 'grass3', 'grass1', 'grass1' },
            dirt = { 'dirt1', 'dirt2', 'dirt3', 'dirt4' },
            breakroom = { 'dirt1' },
            -- clay: Tiny Dungeon's sandy floor, tinted terracotta below
            stone = { 'clay1', 'clay2', 'clay1', 'clay3' },
            -- hard dirt: Tiny Dungeon's dark earth, pebbles and holes
            snow = { 'hard1', 'hard1', 'hard2', 'hard3' },
        },
        tint = { stone = { 0.86, 0.6, 0.5 } },
        woof = 16,
    },
    soft = {
        filter = 'linear', bake = 2,
        ground = {
            grass = { 'grass1', 'grass2', 'grass1' },
            dirt = { 'dirt1', 'dirt2' },
            breakroom = { 'dirt1' },
            water = { 'water1', 'water2' },
            -- clay and hard dirt: the dirt picture in terracotta and in dark
            -- earth (the stone pictures read as walls, the floor as a floor)
            stone = { 'dirt2', 'dirt1' },
            snow = { 'dirt1', 'dirt2' },
        },
        tint = { stone = { 1, 0.66, 0.5 }, snow = { 0.5, 0.38, 0.3 } },
        woof = 64,
    },
}

function Kenney.new(world, skinName)
    local self = View.new(world)
    setmetatable(self, Kenney)
    local skin = Kenney.SKINS[skinName]
    self.skin = skin
    self.skinName = skinName
    self.bake = skin.bake
    self.atlas = love.graphics.newImage(DIR .. skinName .. '.png')
    self.atlas:setFilter(skin.filter, skin.filter)
    local aw, ah = self.atlas:getDimensions()
    self.img = {}
    for name, r in pairs(ATLAS[skinName]) do
        self.img[name] = { quad = love.graphics.newQuad(r[1], r[2], r[3], r[4], aw, ah), w = r[3], h = r[4] }
    end
    if self.bake ~= 1 then
        self.canvas = love.graphics.newCanvas(world.w * TILE_SIZE * self.bake, world.h * TILE_SIZE * self.bake)
        self.canvas:setFilter(skin.filter, skin.filter)
        self.canvasVersion = -1
    end
    return self
end

-- Drawing helpers ----------------------------------------------------------

-- A picture scaled to `tiles` tiles wide, its left edge at px and its
-- bottom on the tile's floor.
function Kenney:sprite(name, px, py, tiles, r, g, b, a)
    local spr = self.img[name]
    if not spr then return false end
    love.graphics.setColor(r or 1, g or 1, b or 1, a or 1)
    local sc = TILE_SIZE * (tiles or 1) / spr.w
    love.graphics.draw(self.atlas, spr.quad, px, py + TILE_SIZE - spr.h * sc, 0, sc, sc)
    return true
end

-- A picture centred on cx, cy and `size` world pixels wide.
function Kenney:centred(name, cx, cy, size, a)
    local spr = self.img[name]
    if not spr then return false end
    local sc = size / spr.w
    love.graphics.setColor(1, 1, 1, a or 1)
    love.graphics.draw(self.atlas, spr.quad, cx, cy, 0, sc, sc, spr.w / 2, spr.h / 2)
    return true
end

function Kenney:pick(set, seed)
    return set[math.floor((seed or 0) * #set) % #set + 1]
end

local function altitudeFactor(self, t)
    local bands = self.world.bands
    local function band(v, lo, hi)
        if hi - lo <= 0 then return 1 end
        return math.max(0, math.min(1, (v - lo) / (hi - lo)))
    end
    if t.type == TILE_WATER then return 0.8 + 0.25 * band(t.altitude, 0, bands.water) end
    if t.type == TILE_GRASS or t.type == TILE_DIRT then return 0.92 + 0.14 * band(t.altitude, bands.water, bands.grass) end
    if t.type == TILE_STONE then return 0.88 + 0.22 * band(t.altitude, bands.grass, bands.stone) end
    return 1
end

-- Ground ------------------------------------------------------------------

function Kenney:drawGround(t, px, py)
    local f = altitudeFactor(self, t)
    local set = self.skin.ground[t.type]
    if t.type == TILE_WATER and not set then
        -- the pixel packs have no water: flat blue with little ripples
        local wf = f
        love.graphics.setColor(0.27 * wf, 0.52 * wf, 0.82 * wf)
        love.graphics.rectangle('fill', px, py, TILE_SIZE, TILE_SIZE)
        love.graphics.setColor(0.6 * wf, 0.8 * wf, 0.98 * wf)
        local o = math.floor((t.colorSeed or 0) * 8)
        love.graphics.rectangle('fill', px + 2 + o, py + 4, 4, 1)
        love.graphics.rectangle('fill', px + 9 - o % 4, py + 11, 4, 1)
        return
    end
    if t.type == TILE_BRIDGE then
        -- planks over the water beneath
        self:drawGround({ type = TILE_WATER, colorSeed = t.colorSeed, altitude = 0, bridgeBase = true }, px, py)
        self:drawBridgePlanks(px, py, 1)
        return
    end
    if t.type == TILE_WALL or t.type == TILE_DOOR then
        self:drawGround({ type = TILE_GRASS, colorSeed = t.colorSeed, altitude = t.altitude }, px, py)
        return
    end
    set = set or self.skin.ground.grass
    local name = self:pick(set, t.colorSeed)
    local c = self.skin.tint and self.skin.tint[t.type] or { 1, 1, 1 }
    self:sprite(name, px, py, 1, c[1] * f, c[2] * f, c[3] * f)
end

local function diggable(t)
    return t and (t.type == TILE_STONE or t.type == TILE_SNOW)
end

-- Clay and hard dirt stand up out of the meadow: a lit top edge and a
-- shadowed foot wherever the neighbour is different ground (also between
-- the two kinds), so each patch reads as one raised bank, not a grid.
function Kenney:drawBankEdges(t, x, y, px, py)
    if not diggable(t) then return end
    local w = self.world
    local function differs(dx, dy)
        local n = w:get(x + dx, y + dy)
        return n ~= nil and n.type ~= t.type
    end
    local T = TILE_SIZE
    if differs(0, -1) then
        love.graphics.setColor(1, 1, 1, 0.28)
        love.graphics.rectangle('fill', px, py, T, 1)
    end
    if differs(0, 1) then
        love.graphics.setColor(0, 0, 0, 0.38)
        love.graphics.rectangle('fill', px, py + T - 2, T, 2)
    end
    love.graphics.setColor(0, 0, 0, 0.2)
    if differs(-1, 0) then love.graphics.rectangle('fill', px, py, 1, T) end
    if differs(1, 0) then love.graphics.rectangle('fill', px + T - 1, py, 1, T) end
end

function Kenney:rebuildCanvas()
    if self.canvasVersion == self.world.version then return end
    self.canvasVersion = self.world.version
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.scale(self.bake, self.bake)
    for x = 1, self.world.w do
        for y = 1, self.world.h do
            local t = self.world.tiles[x][y]
            local px, py = (x - 1) * TILE_SIZE, (y - 1) * TILE_SIZE
            self:drawGround(t, px, py)
            self:drawBankEdges(t, x, y, px, py)
            if t.type == TILE_WALL then
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

function Kenney:drawWorld()
    love.graphics.setColor(1, 1, 1, 1)
    local s = 1 / self.bake
    love.graphics.draw(self.canvas, 0, 0, 0, s, s)
end

-- The home nest: the pixel set lays its plaza under it and a sign over it.
function Kenney:drawBreakroom()
    local br = self.world.breakroom
    if not br then return end
    local px, py = (br.x - 1) * TILE_SIZE, (br.y - 1) * TILE_SIZE
    if self.skinName == 'pixel' and self.img.home_c then
        local T = TILE_SIZE
        local x0, y0 = px - T / 2, py - T / 2
        local rows = { { 'home_tl', 'home_t', 'home_tr' }, { 'home_l', 'home_c', 'home_r' }, { 'home_bl', 'home_b', 'home_br' } }
        for j = 1, 3 do
            for i = 1, 3 do
                self:sprite(rows[j][i], x0 + (i - 1) * T, y0 + (j - 1) * T, 1)
            end
        end
        self:sprite('sign', px + T / 2, py - T / 2, 1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    View.drawBreakroom(self)
end

function Kenney:drawNodes(clock)
    local T = TILE_SIZE
    for _, node in ipairs(self.world.nodes) do
        local px, py = (node.x - 1) * T, (node.y - 1) * T
        if node.kind == NODE_BUSH then
            self:sprite('bush', px, py, 1)
            if node.ready then
                local f = self.img[node.food] and node.food or nil
                if f then self:centred(f, px + 8, py + 8, 7) else
                    local img = self:foodImage(node.food)
                    if img then
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.draw(img, px + 8, py + 7, 0, 0.5, 0.5, 8, 8)
                    end
                end
            end
        elseif node.kind == NODE_TREE then
            if node.ready then self:sprite('tree', px, py, 1) else self:sprite('stump', px, py, 1) end
        elseif node.kind == NODE_ORE then
            local glint = 0.8 + 0.2 * math.sin((clock or 0) * 3 + node.id)
            if self.img.gold then
                self:sprite('gold', px, py, 1, glint, glint, glint)
            else
                love.graphics.setColor(0.95 * glint, 0.8 * glint, 0.2)
                love.graphics.ellipse('fill', px + 6, py + 8, 3.2, 2.4)
                love.graphics.ellipse('fill', px + 11, py + 10, 2.6, 2)
                love.graphics.setColor(1, 0.95, 0.6)
                love.graphics.circle('fill', px + 5, py + 7, 0.9)
            end
        elseif node.kind == NODE_GRASS then
            self:sprite(node.ready and 'grass_tall' or 'grass_cropped', px, py, 1)
        elseif node.kind == NODE_LEAVES then
            self:sprite('leaves', px, py, 1)
        elseif node.kind == NODE_CRITTER then
            local hop = math.abs(math.sin((clock or 0) * 5 + node.id)) * 1.5
            love.graphics.setColor(0, 0, 0, 0.18)
            love.graphics.ellipse('fill', px + 8, py + 13, 4, 1.5)
            self:sprite('critter', px, py - hop, 1)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Buildings ---------------------------------------------------------------

function Kenney:drawFloorSpot(px, py, a)
    self:sprite('stash', px, py, 1, 1, 1, 1, a)
end

function Kenney:drawBin(px, py, a)
    self:sprite('bin', px, py, 1, 1, 1, 1, a)
    self:sprite('bin', px + TILE_SIZE, py, 1, 1, 1, 1, a)
end

function Kenney:drawBed(px, py, a)
    self:sprite('bed', px, py, 1, 1, 1, 1, a)
end

function Kenney:drawWallTile(px, py, a)
    self:sprite('wall', px, py, 1, 1, 1, 1, a)
end

function Kenney:drawDoorTile(px, py, a)
    self:sprite('door', px, py, 1, 1, 1, 1, a)
end

function Kenney:drawFloorTile(px, py, a)
    self:sprite('floor', px, py, 1, 1, 1, 1, a)
end

function Kenney:drawBridgePlanks(px, py, a)
    self:sprite('plank', px, py, 1, 0.95, 0.72, 0.45, a)
end

-- Things on the ground ----------------------------------------------------

-- A food picture: the set's own, else the painted fruit.
function Kenney:drawFood(food, cx, cy, size)
    if self.img[food] then return self:centred(food, cx, cy, size) end
    local img = self:foodImage(food)
    if img then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, cx, cy, 0, size / 16, size / 16, 8, 8)
    end
end

local BIN_SLOTS = { { 6, 8 }, { 12, 8 }, { 20, 8 }, { 26, 8 } }

function Kenney:drawItems(clock)
    for _, item in ipairs(self.world.items) do
        local px, py = (item.x - 1) * TILE_SIZE, (item.y - 1) * TILE_SIZE
        local tile = self.world:get(item.x, item.y)
        local inBin = tile.storage > STORAGE_FLOOR_CAPACITY
        if not inBin then
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.ellipse('fill', px + 8, py + 12, 5, 2)
        end
        if item.kind == ITEM_FOOD then
            if inBin then
                local q = BIN_SLOTS[((item.slot or 1) - 1) % #BIN_SLOTS + 1]
                self:drawFood(item.food, px + q[1], py + q[2], 6)
            else
                self:drawFood(item.food, px + 8, py + 8, 10)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Morphis -----------------------------------------------------------------

function Kenney:drawWorkerBody(w, clock, sx, feetY)
    if w.stage == 'egg' then
        View.drawWorkerBody(self, w, clock, sx, feetY)
        return
    end
    local name = self.img[w.sheet] and w.sheet or 'pupper'
    local spr = self.img[name]
    if w.state == 'quitting' then
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    local size = w.stage == 'baby' and BABY_SCALE or 1
    -- hop, squash, breathing and wiggle from src/feel.lua, as the other looks
    local pose = w.pose or Feel.pose(w, clock)
    local sy = pose.sy
    local face = self.skin.woof == 16 and 16 or 14
    local sc = face / spr.w * size
    love.graphics.push()
    love.graphics.translate(w.x, feetY - pose.hop)
    love.graphics.rotate(pose.rot)
    love.graphics.scale(sx * (2 - sy) * pose.sx * sc, sy * sc)
    love.graphics.draw(self.atlas, spr.quad, 0, 0, 0, 1, 1, spr.w / 2, spr.h)
    local eyes = self:eyesOf(name)
    self:drawFace(eyes, pose, w.state == 'quitting', spr.w / 2, spr.h)
    love.graphics.pop()
    if pose.happy and not eyes then
        -- no face to squint: a little heart pops up instead
        love.graphics.setColor(1, 0.55, 0.7, 1)
        local hx, hy = w.x, feetY - pose.hop - 17
        love.graphics.circle('fill', hx - 1, hy, 1.2)
        love.graphics.circle('fill', hx + 1, hy, 1.2)
        love.graphics.polygon('fill', hx - 2.1, hy + 0.4, hx + 2.1, hy + 0.4, hx, hy + 2.6)
    end
    if pose.wave then
        love.graphics.push()
        love.graphics.translate(w.x, feetY - pose.hop)
        love.graphics.scale(sx * size, size)
        self:drawWaveArm(w, pose.wave, eyes and eyes[1])
        love.graphics.pop()
    end
    local tool = w:toolInHand()
    if tool then
        local swing = 0
        if w.state == 'working' then swing = -0.9 + 0.7 * math.sin((clock or 0) * 12 + w.id) end
        self:drawTool(tool, w.x + 5 * sx, feetY - 6 - pose.hop, swing, sx)
    end
end

-- Where a species' eyes sit in the atlas (the pixel set's 16 px animals have
-- two lone dark pixels; the soft set's smooth art has none, so nil).
function Kenney:eyesOf(name)
    self.eyes = self.eyes or {}
    if self.eyes[name] == nil then
        self.eyes[name] = false
        local r = ATLAS[self.skinName][name]
        if r and r[3] == 16 and love.image and love.image.newImageData then
            local ok, data = pcall(love.image.newImageData, DIR .. self.skinName .. '.png')
            if ok and data and data.getPixel then
                local found = Feel.findEyes(data, 1, 16, r[1], r[2])
                if found[1] then self.eyes[name] = found[1] end
            end
        end
    end
    return self.eyes[name] or nil
end

function Kenney:drawWorkerCargo(w, clock, sx, feetY)
    local cargo = w.slots[SLOT_WORK]
    if cargo and cargo.kind == CARGO_FOOD then
        local bob = (Feel.calm and 0 or math.sin((clock or 0) * 6 + w.id)) - (w.pose and w.pose.hop or 0)
        self:drawFood(cargo.food, w.x, w.y - 15 + bob, 9)
        cargo = nil
    elseif cargo and cargo.kind == CARGO_GOLD and self.img.gold then
        local bob = (Feel.calm and 0 or math.sin((clock or 0) * 6 + w.id)) - (w.pose and w.pose.hop or 0)
        self:centred('gold', w.x, w.y - 15 + bob, 9)
        cargo = nil
    end
    local pocket = w.slots[SLOT_PERSONAL]
    if pocket and pocket.kind == ITEM_FOOD then
        self:drawFood(pocket.food, w.x + 7, feetY - 4, 6)
    end
    if cargo then
        -- sticks, grass, leaves and the painted gold are drawn as the classic set does
        local keep = w.slots[SLOT_PERSONAL]
        w.slots[SLOT_PERSONAL] = nil
        View.drawWorkerCargo(self, w, clock, sx, feetY)
        w.slots[SLOT_PERSONAL] = keep
    end
end

return Kenney
