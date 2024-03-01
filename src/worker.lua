local spritesheet = require('src.drawing.spritesheet')
local object = require('libs.classic')

require('src.constants')
Timer = require('src.system.timer')

LastNewMorphiFrame = 1

Worker = object:extend()
function Worker:new(entity)
    self.height = TILE_SIZE * WORKER_SCALE
    self.width = TILE_SIZE * WORKER_SCALE
    self.facing = LEFT
    self.entity = entity
    self.id = entity.iid
    self.name = entity.props['Name'] or entity.id
    self.morphoType = entity.props['MorphoType'] or MORPHOTYPE_DEFAULT
    self.x = entity.x
    self.y = entity.y
    self.visible = entity.visible
    self.scaleX = WORKER_SCALE
    self.scaleX, self.scaleY = WORKER_SCALE, WORKER_SCALE
    self.spritesheet = love.graphics.newImage('spritesheets/' .. self.morphoType .. '-worker-walk.png')
    self.grid = spritesheet.NewAnim8Grid(self.spritesheet, WORKER_WIDTH, WORKER_HEIGHT)
    self.animations = {}
    self.animations.walk = Anim8.newAnimation(self.grid('1-3', 1), 0.15)
    self.currentAnimation = self.animations.walk
    self.animations.walk:gotoFrame(self:varyFrame(#self.animations.walk.frames))
    self.collider = World:newBSGRectangleCollider(
        self.x,
        self.y,
        self.width,
        self.height,
        2)
    self.collider:setCollisionClass(COLLISION_WORKER)
    self.collider:setFixedRotation(true)
    self.collider:setObject(self)
    self.task = {
        wander = true,
        canFlip = true,
        timer = Timer:add('flip.' .. self.id, 5, function(nym)
                if nym == 'flip.' .. self.id then -- we have to check the payload to see if this signal is for this instances timer expiration...?
                    self:flipFacing()
                end
            end,
            true)
    }
end

function Worker:varyFrame(upTo)
    LastNewMorphiFrame = (LastNewMorphiFrame + 1) % upTo + 1
    local frame = LastNewMorphiFrame
    return frame
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

    if self.task.wander then
        if px == 0 and self.task.canFlip then
            self:flipFacing()
            self.task.canFlip = false
        elseif math.abs(px) > 5 and self.task.canFlip == false then
            self.task.canFlip = true
        end

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
