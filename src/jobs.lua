-- First come, first served job queue. Jobs are typed by the node they point
-- at: 'forage' for bushes, 'chop' for trees, 'mine' for ore. Each role only
-- takes its own type.
require('src.constants')

local Jobs = {}
Jobs.__index = Jobs

local TYPE_FOR_KIND = { bush = 'forage', tree = 'chop', ore = 'mine' }

function Jobs.typeForNode(node)
    return TYPE_FOR_KIND[node.kind]
end

function Jobs.new()
    return setmetatable({ items = {}, clock = 0 }, Jobs)
end

function Jobs:update(dt)
    self.clock = self.clock + dt
end

function Jobs:count(jobType)
    if not jobType then return #self.items end
    local n = 0
    for _, job in ipairs(self.items) do
        if job.type == jobType then n = n + 1 end
    end
    return n
end

function Jobs:hasJobFor(node)
    for _, job in ipairs(self.items) do
        if job.node == node then return true end
    end
    return false
end

function Jobs:post(job, front)
    if job.node and self:hasJobFor(job.node) then
        if front then self:prioritize(job.node) end
        return false
    end
    job.postedAt = job.postedAt or self.clock
    if front then
        table.insert(self.items, 1, job)
    else
        table.insert(self.items, job)
    end
    return true
end

function Jobs:postNode(node, front)
    return self:post({ type = Jobs.typeForNode(node), x = node.x, y = node.y, node = node }, front)
end

-- Move the job for this node to the front of the queue.
function Jobs:prioritize(node)
    for i, job in ipairs(self.items) do
        if job.node == node then
            table.remove(self.items, i)
            table.insert(self.items, 1, job)
            return true
        end
    end
    return false
end

-- Returns and removes the oldest job of the given type that passes the
-- predicate. Jobs whose node is no longer ready are dropped along the way.
function Jobs:take(jobType, predicate)
    local i = 1
    while i <= #self.items do
        local job = self.items[i]
        if job.node and not job.node.ready then
            table.remove(self.items, i)
        elseif (jobType == nil or job.type == jobType) and (predicate == nil or predicate(job)) then
            table.remove(self.items, i)
            return job
        else
            i = i + 1
        end
    end
    return nil
end

function Jobs:remove(job)
    for i, j in ipairs(self.items) do
        if j == job then
            table.remove(self.items, i)
            return true
        end
    end
    return false
end

function Jobs:clear()
    self.items = {}
end

return Jobs
