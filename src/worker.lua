local spritesheet = require('src.drawing.spritesheet')

require('src.constants')

Worker = {
    height = TILE_SIZE * WORKER_SCALE,
    width = TILE_SIZE * WORKER_SCALE,
    facing = LEFT
}
function Worker:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    self.entity = obj
    self.name = obj.id
    self.x = obj.x
    self.y = obj.y
    self.scaleX = WORKER_SCALE
    self.scaleX, self.scaleY = WORKER_SCALE, WORKER_SCALE
    self.spritesheet = love.graphics.newImage('spritesheets/blue-worker-walk.png')
    self.grid = spritesheet.NewAnim8Grid(self.spritesheet, WORKER_WIDTH, WORKER_HEIGHT)
    self.animations = {}
    self.animations.walk = Anim8.newAnimation(self.grid('1-3', 1), 0.3)
    self.currentAnimation = self.animations.walk
    self.collider = World:newBSGRectangleCollider(
        self.x,
        self.y,
        self.width,
        self.height,
        0)
    self.collider:setCollisionClass(COLLISION_WORKER)
    self.collider:setFixedRotation(true)
    self.collider:setObject(self)
    self.task = {}
    return self
end

function Worker:update(dt)
    local px = self.collider:getLinearVelocity()
    World:update(dt)

    self:chooseConstantAnimation(px)
    self.currentAnimation:update(dt)

    if self.task.wander then
        if self.facing == RIGHT and px < MAX_WORKER_SPEED then
            self.collider:applyForce(WORKER_SPEED, 0)
        elseif self.facing == LEFT and px > -MAX_WORKER_SPEED then
            self.collider:applyForce(-WORKER_SPEED, 0)
        end
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

function Worker:resetAnim()
    self.currentAnim8 = self.animations.idle
end

function Worker:chooseConstantAnimation(velocity)
    if self.currentAnim8 ~= self.animations.walk
        and self.currentAnim8 ~= self.animations.idle then
        return
    end
    if velocity == 0 then
        self.currentAnim8 = self.animations.idle
    else
        self.currentAnim8 = self.animations.walk
    end
end

return Worker