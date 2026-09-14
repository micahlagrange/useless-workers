require('src.constants')
local Util = require('src.util')
local Pathfinder = require('src.pathfinder')

local Worker = {}
Worker.__index = Worker
local nextId = 1

function Worker.new(world, jobs, scoring, rng, opts)
    opts = opts or {}
    local self = setmetatable({}, Worker)
    self.id = nextId
    nextId = nextId + 1
    self.world, self.jobs, self.scoring, self.rng = world, jobs, scoring, rng
    self.name = opts.name or ('Employee ' .. self.id)
    self.tint = opts.tint or { 1, 1, 1 }
    self.tintName = opts.tintName or 'white'
    local c = Util.tileCenter(opts.x or 1, opts.y or 1)
    self.x, self.y = c.x, c.y
    self.hunger = HUNGER_MAX
    self.drain = opts.drain or 1.5
    self.speed = opts.speed or WORKER_SPEED
    self.state = 'idle'
    self.stateTimer = 0
    self.decideTimer = rng and rng:random() * DECIDE_INTERVAL or 0
    self.path, self.pathIndex = nil, 1
    self.goal = nil
    self.job = nil
    self.targetTree = nil
    self.carrying = nil
    self.walkTime = 0
    self.icks = {}
    self.facing = 'left'
    self.moving = false
    self.bubble = nil
    self.clock = 0
    self.animTime = 0
    self.alive = true
    self.delivered = 0
    self.complaintCount = 0
    self.onComplain = opts.onComplain
    self.onEvent = opts.onEvent
    return self
end

function Worker:tile()
    return Util.worldToTile(self.x, self.y)
end

function Worker:isWorking()
    return self.alive and self.state ~= 'quitting'
end

function Worker:emit(name, data)
    if self.onEvent then self.onEvent(self, name, data) end
end

function Worker:say(text, ttl)
    self.bubble = { text = text, ttl = ttl or 2.5 }
end

function Worker:isIcked(x, y)
    local expires = self.icks[Util.key(x, y)]
    return expires ~= nil and expires > self.clock
end

function Worker:ick(x, y)
    self.icks[Util.key(x, y)] = self.clock + ICK_SECONDS
end

-- Somebody already complained about this tree recently.
function Worker:recentlyReported(tree)
    return tree.complainedAt ~= nil and (self.clock - tree.complainedAt) < COMPLAINT_COOLDOWN
end

function Worker:face(dx, dy)
    if math.abs(dx) > math.abs(dy) then
        self.facing = dx < 0 and 'left' or 'right'
    elseif dy ~= 0 then
        self.facing = dy < 0 and 'up' or 'down'
    end
end

function Worker:releaseTree()
    if self.targetTree and self.targetTree.claimedBy == self then
        self.targetTree.claimedBy = nil
    end
    self.targetTree = nil
end

-- Put the current job back on the queue and forget the path.
function Worker:dropJob()
    if self.job then
        local job = self.job
        self.job = nil
        if job.tree.ripe then self.jobs:post(job) end
    end
    self:releaseTree()
    self.path = nil
    self.goal = nil
end

function Worker:complain(reason, x, y)
    local tree = self.targetTree or (self.job and self.job.tree)
    if tree then tree.complainedAt = self.clock end
    self.scoring:addComplaint()
    self.complaintCount = self.complaintCount + 1
    self:say('!!')
    if x and y then self:ick(x, y) end
    if self.onComplain then self.onComplain(self, reason, x, y) end
    self:emit('complain', reason)
    self:dropJob()
    self.state = 'sulking'
    self.stateTimer = WORKER_SULK_SECONDS
end

function Worker:quit()
    self:dropJob()
    self.carrying = nil
    self.scoring:addQuit()
    self:say('I QUIT', 6)
    self:emit('quit')
    self.state = 'quitting'
    local t = self:tile()
    local choices = {
        { dx = -1, dy = 0, d = t.x },
        { dx = 1, dy = 0, d = self.world.w - t.x },
        { dx = 0, dy = -1, d = t.y },
        { dx = 0, dy = 1, d = self.world.h - t.y },
    }
    table.sort(choices, function(a, b) return a.d < b.d end)
    self.exitDir = choices[1]
end

function Worker:setPath(path, goal)
    self.path = path
    self.pathIndex = 1
    self.goal = goal
    self.walkTime = 0
    self.state = 'walking'
    local t = self:tile()
    if path[1] and path[1].x == t.x and path[1].y == t.y then
        self.pathIndex = 2
    end
    if self.pathIndex > #path then self:arrive() end
end

function Worker:pathTo(x, y)
    local t = self:tile()
    return Pathfinder.find(self.world, t.x, t.y, x, y)
end

-- Nearest ripe, unclaimed, not icked tree the worker can reach. Second return
-- value is the nearest such tree that is walled off, if any.
function Worker:nearestRipeTree()
    local best, bestD = nil, math.huge
    local blocked, blockedD = nil, math.huge
    for _, tree in ipairs(self.world.trees) do
        if tree.ripe and tree.claimedBy == nil and not self:isIcked(tree.x, tree.y) then
            local c = Util.tileCenter(tree.x, tree.y)
            local d = Util.dist(self.x, self.y, c.x, c.y)
            if self.world:isReachable(tree.x, tree.y) then
                if d < bestD then best, bestD = tree, d end
            elseif d < blockedD and not self:recentlyReported(tree) then
                blocked, blockedD = tree, d
            end
        end
    end
    return best, blocked
end

function Worker:decide()
    -- 1. Survival beats output
    if self.hunger < HUNGER_EAT_THRESHOLD then
        local tree, blocked = self:nearestRipeTree()
        if tree then
            local path = self:pathTo(tree.x, tree.y)
            if path then
                tree.claimedBy = self
                self.targetTree = tree
                self:setPath(path, 'eat')
                return
            end
        elseif blocked then
            blocked.complainedAt = self.clock
            self:complain('hungry', blocked.x, blocked.y)
            return
        end
    end
    -- 2. Oldest job on the queue
    local job = self.jobs:take(function(j)
        if not j.tree.ripe or j.tree.claimedBy ~= nil or self:isIcked(j.x, j.y) then return false end
        if self:recentlyReported(j.tree) and not self.world:isReachable(j.x, j.y) then return false end
        return true
    end)
    if job then
        self.job = job
        if not self.world:isReachable(job.x, job.y) then
            self:complain('blocked', job.x, job.y)
            return
        end
        local path = self:pathTo(job.x, job.y)
        if path then
            job.tree.claimedBy = self
            self.targetTree = job.tree
            self:setPath(path, 'harvest')
        else
            self:complain('blocked', job.x, job.y)
        end
        return
    end
    -- 3. Wander
    local t = self:tile()
    local target = self.rng and self.world:randomNearbyPassable(self.rng, t.x, t.y, WANDER_RADIUS)
    if target then
        local path = self:pathTo(target.x, target.y)
        if path then
            self:setPath(path, 'wander')
            return
        end
    end
    self.decideTimer = DECIDE_INTERVAL * 2
end

function Worker:followPath(dt)
    -- The tree we were walking to got eaten by somebody else
    if (self.goal == 'harvest' or self.goal == 'eat') and self.targetTree and not self.targetTree.ripe then
        self:releaseTree()
        self.job = nil
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        return
    end
    self.walkTime = self.walkTime + dt
    if self.walkTime > WORKER_PATIENCE and (self.goal == 'harvest' or self.goal == 'eat') then
        local tx = self.targetTree and self.targetTree.x
        local ty = self.targetTree and self.targetTree.y
        self:complain('slow', tx, ty)
        return
    end
    local node = self.path and self.path[self.pathIndex]
    if not node then
        self:arrive()
        return
    end
    local c = Util.tileCenter(node.x, node.y)
    local dx, dy = c.x - self.x, c.y - self.y
    local d = math.sqrt(dx * dx + dy * dy)
    local step = self.speed * dt
    self.moving = true
    if d <= step then
        self.x, self.y = c.x, c.y
        self.pathIndex = self.pathIndex + 1
        if self.pathIndex > #self.path then self:arrive() end
    else
        self.x = self.x + dx / d * step
        self.y = self.y + dy / d * step
        self:face(dx, dy)
    end
end

function Worker:arrive()
    self.path = nil
    self.moving = false
    if self.goal == 'eat' then
        self.state = 'eating'
        self.stateTimer = EAT_SECONDS
    elseif self.goal == 'harvest' then
        self.state = 'harvesting'
        self.stateTimer = HARVEST_SECONDS
    elseif self.goal == 'deliver' then
        self.scoring:addOutput()
        self.delivered = self.delivered + 1
        self.carrying = nil
        self:emit('deliver')
        self.goal = nil
        self.state = 'idle'
    else
        self.goal = nil
        self.state = 'idle'
    end
end

function Worker:finishAction()
    if self.state == 'eating' then
        if self.targetTree and self.targetTree.ripe then
            self.hunger = math.min(HUNGER_MAX, self.hunger + FRUIT_HUNGER_VALUE)
            self.world:harvest(self.targetTree)
            self:emit('eat')
        end
        self:releaseTree()
        self.goal = nil
        self.state = 'idle'
    elseif self.state == 'harvesting' then
        local picked = false
        if self.targetTree and self.targetTree.ripe then
            self.world:harvest(self.targetTree)
            if self.hunger < HUNGER_EAT_THRESHOLD then
                -- too hungry to carry it back, eat it on the spot
                self.hunger = math.min(HUNGER_MAX, self.hunger + FRUIT_HUNGER_VALUE)
                self:emit('eat')
            else
                self.carrying = self.targetTree.fruit or 1
                self:emit('harvest')
                picked = true
            end
        end
        self:releaseTree()
        self.job = nil
        if picked then
            local t = self:tile()
            local br = self.world:nearestBreakroomTile(t.x, t.y)
            local path = br and self:pathTo(br.x, br.y)
            if path then
                self:setPath(path, 'deliver')
                return
            end
            self.carrying = nil
        end
        self.goal = nil
        self.state = 'idle'
    end
end

function Worker:update(dt, clock)
    self.clock = clock or (self.clock + dt)
    self.animTime = self.animTime + dt
    if self.bubble then
        self.bubble.ttl = self.bubble.ttl - dt
        if self.bubble.ttl <= 0 then self.bubble = nil end
    end
    if not self.alive then return end
    if self.state == 'quitting' then
        local d = self.exitDir
        self.x = self.x + d.dx * self.speed * dt
        self.y = self.y + d.dy * self.speed * dt
        self:face(d.dx, d.dy)
        self.moving = true
        local t = self:tile()
        if not self.world:inBounds(t.x, t.y) then self.alive = false end
        return
    end
    self.hunger = self.hunger - self.drain * dt
    if self.carrying and self.hunger < HUNGER_STARVING then
        -- eats the delivery rather than starve
        self.hunger = math.min(HUNGER_MAX, self.hunger + FRUIT_HUNGER_VALUE)
        self.carrying = nil
        self:emit('eat')
        self:say('mine now')
        self.path = nil
        self.goal = nil
        self.state = 'idle'
    end
    if self.hunger <= 0 then
        self.hunger = 0
        self:quit()
        return
    end
    self.moving = false
    if self.state == 'idle' then
        self.decideTimer = self.decideTimer - dt
        if self.decideTimer <= 0 then
            self.decideTimer = DECIDE_INTERVAL
            self:decide()
        end
    elseif self.state == 'sulking' then
        self.stateTimer = self.stateTimer - dt
        if self.stateTimer <= 0 then self.state = 'idle' end
    elseif self.state == 'walking' then
        self:followPath(dt)
    elseif self.state == 'eating' or self.state == 'harvesting' then
        self.stateTimer = self.stateTimer - dt
        if self.stateTimer <= 0 then self:finishAction() end
    end
end

function Worker:describeState()
    if self.state == 'quitting' then return 'Quitting' end
    if self.state == 'sulking' then return 'Complaining' end
    if self.state == 'eating' then return 'Eating' end
    if self.state == 'harvesting' then return 'Picking' end
    if self.state == 'walking' then
        if self.goal == 'deliver' then return 'Carrying to break room' end
        if self.goal == 'eat' then return 'Going to eat' end
        if self.goal == 'harvest' then return 'Going to pick' end
        return 'Wandering'
    end
    return 'Idle'
end

return Worker
