-- A morphi. Has a role (forager, lumberjack, miner), gets hungry, takes jobs
-- of its own type off the shared queue, complains when it cannot reach them,
-- carries a work item in slot 1 and a personal snack in slot 2, and takes a
-- break in the break room after enough work. Nothing interrupts a job:
-- eating, fetching a snack and taking a break are all chosen while idle.
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
    self.role = opts.role or ROLE_FORAGER
    self.roleInfo = ROLES[self.role]
    self.sheet = opts.sheet or self.roleInfo.sheets[1]
    self.species = MORPHI_SHEET_NAMES[self.sheet] or self.sheet
    self.name = opts.name or ('Morphi ' .. self.id)
    local c = Util.tileCenter(opts.x or 1, opts.y or 1)
    self.x, self.y = c.x, c.y
    self.hunger = HUNGER_MAX
    self.drain = opts.drain or 0.7
    self.speed = opts.speed or WORKER_SPEED
    self.state = 'idle'
    self.stateTimer = 0
    self.decideTimer = rng and rng:random() * DECIDE_INTERVAL or 0
    self.path, self.pathIndex = nil, 1
    self.goal = nil
    self.job = nil
    self.targetNode = nil
    self.targetItem = nil
    self.targetTile = nil
    self.slots = {}           -- [SLOT_WORK] = {kind, fruit}, [SLOT_PERSONAL] = {kind, fruit}
    self.eatingSlot = nil
    self.workTime = 0         -- accumulated work since the last break
    self.wantsBreak = false
    self.breaksTaken = 0
    self.walkTime = 0
    self.icks = {}
    self.facing = 'right'
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

-- Inventory -------------------------------------------------------------

function Worker:carrying()
    return self.slots[SLOT_WORK]
end

function Worker:snackInPocket()
    local s = self.slots[SLOT_PERSONAL]
    return s ~= nil and s.kind == ITEM_FOOD
end

function Worker:hasFoodInSlot(i)
    local s = self.slots[i]
    return s ~= nil and s.kind == ITEM_FOOD
end

function Worker:tile()
    return Util.worldToTile(self.x, self.y)
end

function Worker:isWorking()
    return self.alive and self.state ~= 'quitting'
end

function Worker:title()
    return self.name .. ' the ' .. self.species .. ' (' .. self.roleInfo.label:lower() .. ')'
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

function Worker:recentlyReported(node)
    return node.complainedAt ~= nil and (self.clock - node.complainedAt) < COMPLAINT_COOLDOWN
end

function Worker:face(dx, dy)
    if dx < 0 then
        self.facing = 'left'
    elseif dx > 0 then
        self.facing = 'right'
    end
end

function Worker:releaseNode()
    if self.targetNode and self.targetNode.claimedBy == self then
        self.targetNode.claimedBy = nil
    end
    self.targetNode = nil
end

function Worker:releaseItem()
    if self.targetItem and self.targetItem.claimedBy == self then
        self.targetItem.claimedBy = nil
    end
    self.targetItem = nil
end

function Worker:releaseTile()
    if self.targetTile then
        self.world:releaseReservations(self)
        self.targetTile = nil
    end
end

-- Put the current job back on the queue and forget the path.
function Worker:dropJob()
    if self.job then
        local job = self.job
        self.job = nil
        if job.node.ready then self.jobs:post(job) end
    end
    self:releaseNode()
    self:releaseItem()
    self:releaseTile()
    self.path = nil
    self.goal = nil
end

function Worker:complain(reason, node)
    if node then node.complainedAt = self.clock end
    self.scoring:addComplaint()
    self.complaintCount = self.complaintCount + 1
    self:say('!!')
    if node then self:ick(node.x, node.y) end
    if self.onComplain then self.onComplain(self, reason, node) end
    self:emit('complain', reason)
    self:dropJob()
    self.state = 'sulking'
    self.stateTimer = WORKER_SULK_SECONDS
end

function Worker:quit()
    self:dropJob()
    self.slots = {}
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

-- Movement --------------------------------------------------------------

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

function Worker:pathToBreakroom()
    local t = self:tile()
    local br = self.world:nearestBreakroomTile(t.x, t.y)
    return br and self:pathTo(br.x, br.y)
end

-- After idling on top of a stored item or the furniture, move one tile over.
function Worker:stepOff()
    local t = self:tile()
    local tile = self.world:get(t.x, t.y)
    if not tile or (not tile.item and tile.type ~= TILE_BREAKROOM) then return false end
    local spot = self.world:freeNeighbour(t.x, t.y)
    if not spot then return false end
    local path = self:pathTo(spot.x, spot.y)
    if not path then return false end
    self:setPath(path, 'wander')
    return true
end

-- Eating ----------------------------------------------------------------

-- Eat from a slot. Only ever chosen while idle, like any other job.
function Worker:snack(slot)
    if not self:hasFoodInSlot(slot) then return false end
    self.eatingSlot = slot
    self.state = 'eating'
    self.stateTimer = EAT_SECONDS
    self.moving = false
    return true
end

function Worker:finishEating()
    if self.eatingSlot then
        if self:hasFoodInSlot(self.eatingSlot) then
            self.slots[self.eatingSlot] = nil
            self.hunger = math.min(HUNGER_MAX, self.hunger + FRUIT_HUNGER_VALUE)
            self:emit('eat')
        end
        self.eatingSlot = nil
    elseif self.targetNode and self.targetNode.ready then
        -- eating straight off a bush
        self.hunger = math.min(HUNGER_MAX, self.hunger + FRUIT_HUNGER_VALUE)
        self.world:harvestNode(self.targetNode)
        self:emit('eat')
        self:releaseNode()
    end
    self.goal = nil
    self.state = 'idle'
    self.decideTimer = 0
end

-- Nearest ripe, unclaimed, not icked bush the morphi can reach. Second return
-- value is the nearest such bush that is walled off, if any.
function Worker:nearestRipeBush()
    local best, bestD = nil, math.huge
    local blocked, blockedD = nil, math.huge
    for _, node in ipairs(self.world.nodes) do
        if node.kind == NODE_BUSH and node.ready and node.claimedBy == nil and not self:isIcked(node.x, node.y) then
            local c = Util.tileCenter(node.x, node.y)
            local d = Util.dist(self.x, self.y, c.x, c.y)
            if self.world:isReachable(node.x, node.y) then
                if d < bestD then best, bestD = node, d end
            elseif d < blockedD and not self:recentlyReported(node) then
                blocked, blockedD = node, d
            end
        end
    end
    return best, blocked
end

-- Walk to a stored food item and put it in the personal slot.
function Worker:fetchFood()
    if self.slots[SLOT_PERSONAL] then return false end
    local t = self:tile()
    local item = self.world:nearestStoredItem(ITEM_FOOD, t.x, t.y)
    if not item then return false end
    local path = self:pathTo(item.x, item.y)
    if not path then return false end
    item.claimedBy = self
    self.targetItem = item
    self:setPath(path, 'fetch')
    return true
end

function Worker:eatSomething()
    if self:snackInPocket() then return self:snack(SLOT_PERSONAL) end
    if self:fetchFood() then return true end
    local bush, blocked = self:nearestRipeBush()
    if bush then
        local path = self:pathTo(bush.x, bush.y)
        if path then
            bush.claimedBy = self
            self.targetNode = bush
            self:setPath(path, 'eat')
            return true
        end
    elseif blocked then
        self:complain('hungry', blocked)
        return true
    end
    return false
end

-- Head for the break room, grabbing a snack from storage on the way if the
-- pocket is empty.
function Worker:startBreak()
    self.wantsBreak = true
    if not self.slots[SLOT_PERSONAL] and self:fetchFood() then return true end
    local path = self:pathToBreakroom()
    if path then
        self:setPath(path, 'break')
        return true
    end
    self.wantsBreak = false
    self.workTime = 0
    return false
end

-- Decisions ---------------------------------------------------------------

function Worker:decide()
    -- 1. Survival beats output
    if self.hunger < HUNGER_EAT_THRESHOLD then
        if self:eatSomething() then return end
    end
    -- 2. Earned a break
    if self.workTime >= BREAK_AFTER_SECONDS or self.wantsBreak then
        if self:startBreak() then return end
    end
    -- 3. Oldest job of my type
    local job = self.jobs:take(self.roleInfo.jobType, function(j)
        if not j.node.ready or j.node.claimedBy ~= nil or self:isIcked(j.x, j.y) then return false end
        if self:recentlyReported(j.node) and not self.world:nodeReachable(j.node) then return false end
        return true
    end)
    if job then
        self.job = job
        local spot = self.world:approachTile(job.node)
        if not spot then
            self:complain('blocked', job.node)
            return
        end
        local path = self:pathTo(spot.x, spot.y)
        if path then
            job.node.claimedBy = self
            self.targetNode = job.node
            self:setPath(path, 'work')
        else
            self:complain('blocked', job.node)
        end
        return
    end
    -- 4. Do not loiter on the pantry
    if self:stepOff() then return end
    -- 5. Wander
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
    if (self.goal == 'work' or self.goal == 'eat') and self.targetNode and not self.targetNode.ready then
        self:releaseNode()
        self.job = nil
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        return
    end
    if self.goal == 'fetch' and self.targetItem and self.world:get(self.targetItem.x, self.targetItem.y).item ~= self.targetItem then
        self:releaseItem()
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
        return
    end
    self.walkTime = self.walkTime + dt
    if self.walkTime > WORKER_PATIENCE and (self.goal == 'work' or self.goal == 'eat') then
        self:complain('slow', self.targetNode)
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

-- Carry the work item home: food goes onto a storage tile, logs and gold
-- are handed in at the break room.
function Worker:goDeliver()
    local cargo = self:carrying()
    if not cargo then return false end
    local path
    if cargo.kind == CARGO_FOOD then
        local spot = self.world:nearestFreeStorageTile(self)
        if not spot then
            self:say('no room!')
            return false
        end
        self.world:reserveTile(spot.x, spot.y, self)
        self.targetTile = spot
        path = self:pathTo(spot.x, spot.y)
    else
        path = self:pathToBreakroom()
    end
    if path then
        self:setPath(path, 'deliver')
        return true
    end
    self:releaseTile()
    return false
end

function Worker:deliverHere()
    local cargo = self:carrying()
    if not cargo then return end
    local t = self:tile()
    if cargo.kind == CARGO_FOOD then
        local tile = self.world:get(t.x, t.y)
        if tile.item or not tile.passable then
            -- somebody got here first, find another tile
            self:releaseTile()
            if self:goDeliver() then return end
            return
        end
        self.world:storeItem(ITEM_FOOD, t.x, t.y, cargo.fruit)
        self:releaseTile()
    end
    self.slots[SLOT_WORK] = nil
    self.scoring:addDelivery(cargo.kind)
    self.delivered = self.delivered + 1
    self:emit('deliver', cargo.kind)
    self.goal = nil
    self.state = 'idle'
    self.decideTimer = 0
    if cargo.kind == CARGO_FOOD then self:stepOff() end
end

function Worker:arrive()
    self.path = nil
    self.moving = false
    if self.goal == 'eat' then
        self.state = 'eating'
        self.stateTimer = EAT_SECONDS
    elseif self.goal == 'fetch' then
        local t = self:tile()
        local tile = self.world:get(t.x, t.y)
        if tile.item and tile.item == self.targetItem then
            local item = self.world:takeItem(t.x, t.y)
            self.slots[SLOT_PERSONAL] = { kind = item.kind, fruit = item.fruit }
            self:emit('pickup', item.kind)
        end
        self:releaseItem()
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
        if self.hunger < HUNGER_EAT_THRESHOLD and self:snackInPocket() then
            self:snack(SLOT_PERSONAL)
        elseif self.wantsBreak then
            local path = self:pathToBreakroom()
            if path then self:setPath(path, 'break') else self.wantsBreak = false; self.workTime = 0 end
        end
    elseif self.goal == 'break' then
        self.state = 'breaking'
        self.stateTimer = BREAK_SECONDS
        self:say('break', 2)
    elseif self.goal == 'work' then
        self.state = 'working'
        self.stateTimer = self.roleInfo.actionSeconds
    elseif self.goal == 'deliver' then
        self:deliverHere()
    else
        self.goal = nil
        self.state = 'idle'
    end
end

function Worker:finishAction()
    if self.state == 'eating' then
        self:finishEating()
    elseif self.state == 'breaking' then
        self.workTime = 0
        self.wantsBreak = false
        self.breaksTaken = self.breaksTaken + 1
        self:emit('break')
        self.state = 'idle'
        self.decideTimer = 0
        self:stepOff()
    elseif self.state == 'working' then
        local cargo = nil
        if self.targetNode and self.targetNode.ready then
            local node = self.targetNode
            local kind = self.world:harvestNode(node)
            cargo = { kind = kind, fruit = node.fruit }
            self:emit('work', node.kind)
        end
        self:releaseNode()
        self.job = nil
        if cargo then
            self.slots[SLOT_WORK] = cargo
            if self:goDeliver() then return end
            self.slots[SLOT_WORK] = nil
        end
        self.goal = nil
        self.state = 'idle'
    end
end

function Worker:accumulateWork(dt)
    if self.state == 'working' or (self.state == 'walking' and (self.goal == 'work' or self.goal == 'deliver')) then
        self.workTime = self.workTime + dt
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
    if self.hunger <= 0 then
        self.hunger = 0
        self:quit()
        return
    end
    self:accumulateWork(dt)
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
    elseif self.state == 'eating' or self.state == 'working' or self.state == 'breaking' then
        self.stateTimer = self.stateTimer - dt
        if self.stateTimer <= 0 then self:finishAction() end
    end
end

function Worker:describeState()
    if self.state == 'quitting' then return 'Quitting' end
    if self.state == 'sulking' then return 'Complaining' end
    if self.state == 'eating' then return 'Eating' end
    if self.state == 'breaking' then return 'On a break' end
    if self.state == 'working' then return self.roleInfo.verb:sub(1, 1):upper() .. self.roleInfo.verb:sub(2) end
    if self.state == 'walking' then
        if self.goal == 'deliver' then
            local c = self:carrying()
            return 'Carrying ' .. (c and c.kind or 'cargo') .. (c and c.kind == CARGO_FOOD and ' to storage' or ' to the break room')
        end
        if self.goal == 'eat' then return 'Going to eat' end
        if self.goal == 'fetch' then return 'Fetching a snack from storage' end
        if self.goal == 'break' then return 'Heading to the break room' end
        if self.goal == 'work' then return 'Going ' .. self.roleInfo.verb end
        return 'Wandering'
    end
    return 'Idle'
end

return Worker
