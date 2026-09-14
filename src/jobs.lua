-- First come, first served job queue. The only job type this jam is 'harvest'.
local Jobs = {}
Jobs.__index = Jobs

function Jobs.new()
    return setmetatable({ items = {}, clock = 0 }, Jobs)
end

function Jobs:update(dt)
    self.clock = self.clock + dt
end

function Jobs:count()
    return #self.items
end

function Jobs:hasJobFor(tree)
    for _, job in ipairs(self.items) do
        if job.tree == tree then return true end
    end
    return false
end

function Jobs:post(job, front)
    if job.tree and self:hasJobFor(job.tree) then
        if front then self:prioritize(job.tree) end
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

function Jobs:postHarvest(tree, front)
    return self:post({ type = 'harvest', x = tree.x, y = tree.y, tree = tree }, front)
end

-- Move the job for this tree to the front of the queue.
function Jobs:prioritize(tree)
    for i, job in ipairs(self.items) do
        if job.tree == tree then
            table.remove(self.items, i)
            table.insert(self.items, 1, job)
            return true
        end
    end
    return false
end

-- Returns and removes the oldest job that passes the predicate. Jobs whose
-- tree is no longer ripe are dropped along the way.
function Jobs:take(predicate)
    local i = 1
    while i <= #self.items do
        local job = self.items[i]
        if job.tree and not job.tree.ripe then
            table.remove(self.items, i)
        elseif predicate == nil or predicate(job) then
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
