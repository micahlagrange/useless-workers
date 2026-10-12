local queue = require('src.behavior.queue')
local Timers = require('src.system.timer')
local pubsub = require('src.system.pub-sub')
require('src.constants')

local jobs = queue:extend() -- jobs is an instance of queue

function jobs:pushright(job)
  jobs.super.pushright(self, job)
  pubsub:publish(EVENTS.Jobs.ADDED_JOB, job)
end

return jobs()
