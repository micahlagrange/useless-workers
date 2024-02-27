local spritesheet = require('src.drawing.spritesheet')

require('src.constants')

Worker = {}
function Worker:new(entity)
    local obj = {
        --defaults
        height = TILE_SIZE * WORKER_SCALE,
        width = TILE_SIZE * WORKER_SCALE,
        facing = LEFT
    }
    setmetatable(obj, self)
    self.__index = self

    obj.entity = entity
    obj.id = entity.id
    obj.name = entity.props['Name'] or entity.id
    obj.x = entity.x
    obj.y = entity.y
    obj.visible = entity.visible
    obj.scaleX = WORKER_SCALE
    obj.scaleX, obj.scaleY = WORKER_SCALE, WORKER_SCALE
    obj.spritesheet = love.graphics.newImage('spritesheets/blue-worker-walk.png')
    obj.grid = spritesheet.NewAnim8Grid(obj.spritesheet, WORKER_WIDTH, WORKER_HEIGHT)
    obj.animations = {}
    obj.animations.walk = Anim8.newAnimation(obj.grid('1-3', 1), 0.5)
    obj.currentAnimation = obj.animations.walk
    obj.collider = World:newBSGRectangleCollider(
        obj.x,
        obj.y,
        obj.width,
        obj.height,
        2)
    obj.collider:setCollisionClass(COLLISION_WORKER)
    obj.collider:setFixedRotation(true)
    obj.collider:setObject(obj)
    obj.task = { wander = true, canFlip = true }
    return obj
end

function Worker:flipFacing()
    if self.facing == RIGHT then
        self.facing = LEFT
    elseif self.facing == LEFT then
        self.facing = RIGHT
    end
end

function Worker:update(dt)
    local px = self.collider:getLinearVelocity()

    self:chooseConstantAnimation(px)
    self.currentAnimation:update(dt)

    if px == 0 and self.task.canFlip then
        self:flipFacing()
        self.task.canFlip = false
    elseif math.abs(px) > 5 and self.task.canFlip == false then
        self.task.canFlip = true
    end

    if self.task.wander then
        if self.facing == RIGHT and px < MAX_WORKER_SPEED then
            self.collider:applyForce(WORKER_SPEED, 0)
        elseif self.facing == LEFT and px > -MAX_WORKER_SPEED then
            self.collider:applyForce(-WORKER_SPEED, 0)
        end
    end

    -- Update worker position based on collider
    self.x, self.y = self.collider:getX(), self.collider:getY()
end

function Worker:draw()
    if not self.visible then return end
    local scaleX
    local adjustedX

    if self.facing == RIGHT then
        scaleX = self.scaleX
        adjustedX = self.x
    else
        -- workers origin is their left side, so when the image
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
