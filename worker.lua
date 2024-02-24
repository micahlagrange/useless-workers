local spritesheet = require('spritesheet')

require('constants')

Worker = {
    height = TILE_SIZE * WORKER_SCALE,
    width = TILE_SIZE * WORKER_SCALE,
    facing = LEFT
}

function Worker:new(x, y, obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    obj.x = x
    obj.y = y
    obj.spritesheet = love.graphics.newImage('spritesheets/blue-worker-walk.png')
    obj.grid = spritesheet.NewAnim8Grid(obj.spritesheet, WORKER_WIDTH, WORKER_HEIGHT)
    obj.animations = {}
    obj.animations.walk = Anim8.newAnimation(obj.grid('1-3', 1), obj.spritesheet)
    obj.currentAnimation = obj.animations.walk
end

function Worker:update(dt)
    local px = self.collider:getLinearVelocity()

    self:chooseConstantAnimation(px)
    self.currentAnimation:update(dt)

    if self.facing == RIGHT and px < MAX_WORKER_SPEED then
        self.collider:applyForce(WORKER_SPEED, 0)
    elseif self.facing == LEFT and px > -MAX_WORKER_SPEED then
        self.collider:applyForce(-WORKER_SPEED, 0)
    end

    -- Update player position based on collider
    self.x, self.y = self.collider:getX(), self.collider:getY()
end

function Worker:draw()
    local scaleX
    local adjustedX

    if self.facing == RIGHT then
        scaleX = self.scaleX
        adjustedX = self.x
    else
        -- characters origin is their left side, so when the image
        -- flips we need to push them right
        adjustedX = self.x + self.width
        scaleX = -self.scaleX
    end

    self.currentAnimation:draw(
        self.spritesheet,
        adjustedX - self.width / 2,
        self.y - self.height / 2,
        0,
        scaleX,
        self.scaleY)
end
