local inspect = require('libs.inspect')
local spritesheet = require('src.drawing.spritesheet')
local object = require('libs.classic')
local pubsub = require('src.system.pub-sub')

require('src.constants')
local JobQueue = require('src.behavior.task')

LastNewMorphiFrame = 1

Worker = object:extend()
function Worker:new(entity)
    self.height = TILE_SIZE * MORPHI_SCALE
    self.width = TILE_SIZE * MORPHI_SCALE
    self.facing = LEFT
    self.entity = entity
    self.id = entity.iid
    self.name = entity.props['Name'] or entity.id
    self.morphoType = entity.props['MorphoType'] or MORPHOTYPE_DEFAULT
    self.x = entity.x
    self.y = entity.y
    self.visible = entity.visible
    self.scaleX, self.scaleY = MORPHI_SCALE, MORPHI_SCALE
    self.jobIcon = love.graphics.newImage('icons/job-indicator-icon.png')
    self.spritesheet = love.graphics.newImage('spritesheets/' .. self.morphoType .. '-worker-walk.png')
    self.grid = spritesheet.NewAnim8Grid(self.spritesheet, MORPHI_WIDTH, MORPHI_HEIGHT)
    self.animations = {}
    self.animations.walk = Anim8.newAnimation(self.grid('1-3', 1), 0.15)
    self.animations.idle = Anim8.newAnimation(self.grid('2-3', 1), 1)
    self.currentAnimation = self.animations.idle
    self.animations.walk:gotoFrame(self:varyFrame(#self.animations.walk.frames))
    self.collider = World:newBSGRectangleCollider(
        self.x,
        self.y,
        self.width,
        self.height,
        2)
    self.collider:setCollisionClass(Colliders.MORPHI)
    self.collider:setFixedRotation(true)
    self.collider:setObject(self)
    self.task = { finished = true }
    pubsub:subscribe(EVENTS.Jobs.ADDED_JOB, function() self:takeJob() end)
end

function Worker:varyFrame(upTo)
    LastNewMorphiFrame = (LastNewMorphiFrame + 1) % upTo + 1
    local frame = LastNewMorphiFrame
    return frame
end

function Worker:takeJob()
    if self.task == nil or self.task.finished then
        local success, task = pcall(JobQueue.popleft, JobQueue)
        if not success then
            print(task); return
        end
        -- fake shit:
        self.task           = task
        local takeWanderJob = require('src.behavior.jobs')
        takeWanderJob(self)
        print(self.morphoType, ' took a task! ', self.task.name)
    end
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

    if self.collider:enter(Colliders.CONSUMABLE) then
        local collided = self.collider:getEnterCollisionData(Colliders.CONSUMABLE)
        local food = collided.collider:getObject().consuminstance
        self.hunger:remediate(food:eat())
    end

    if self.task.name == 'wander' then
        if px == 0 and self.task.canFlip then
            self.task.canFlip = false
            self:flipFacing()
        elseif math.abs(px) > 5 then
            self.task.canFlip = true
        end

        if self.facing == RIGHT and px < MAX_WORKER_SPEED then
            self.collider:applyForce(MORPHI_SPEED, 0)
        elseif self.facing == LEFT and px > -MAX_WORKER_SPEED then
            self.collider:applyForce(-MORPHI_SPEED, 0)
        end
    end

    -- Update worker position based on collider
    self.x, self.y = self.collider:getX(), self.collider:getY()
end

function Worker:drawJobIndicator()
    local scale = .7
    if self.task ~= nil and not self.task.finished then
        love.graphics.draw(self.jobIcon,
            self.x - self.jobIcon:getWidth() / 2 * scale,
            self.y - self.height,
            0, scale, scale)
    end
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
    self:drawJobIndicator()
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
