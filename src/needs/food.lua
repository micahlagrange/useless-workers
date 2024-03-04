local object = require('libs.classic')
local Consumables = require('src.system.consumable')
local food = object:extend()

local foodsheet = love.graphics.newImage('spritesheets/yummy_prizes2.png')

function food:new()
    local scale = .5
    local windowWidth, windowHeight = love.window.getMode()
    local quadImageHeight = 16
    local fx = love.math.random(0, 4) * quadImageHeight
    local fy = love.math.random(0, 15) * quadImageHeight
    print(fx, fy)
    self.quad = love.graphics.newQuad(fx, fy, 16, 16, foodsheet)
    -- self.x = windowWidth / 2
    self.x = 48 + love.math.random(5, 11)
    self.y = 16
    self.width = TILE_SIZE * scale
    self.height = TILE_SIZE * scale
    self.scale = .5
    self.consumable = Consumables.New(self.x, self.y, scale)
end

function food:update()
    self.consumable:update()
    self.x = self.consumable.x
    self.y = self.consumable.y
end

function food:draw()
    love.graphics.draw(foodsheet,
        self.quad,
        self.x, self.y,
        self.consumable.angle,
        self.scale, self.scale,
        self.height, self.width
    )
end

return food