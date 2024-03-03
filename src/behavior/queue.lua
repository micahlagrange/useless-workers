local object = require('libs.classic')
local inspect = require('libs.inspect')

List = object:extend()
function List:new()
    self.list = { first = 0, last = -1 }
end

-- function List:pushleft(value)
--     local first = self.list.first - 1
--     self.list.first = first
--     self.list[first] = value
-- end

function List:pushright(value)
    print('pushed ', value)
    local last = self.list.last + 1
    self.list.last = last
    self.list[last] = value
end

function List:popleft()
    local first = self.list.first
    if first > self.list.last then error("list is empty") end
    local value = self.list[first]
    self.list[first] = nil -- to allow garbage collection
    self.list.first = first + 1
    return value
end

-- function List:popright()
--     local last = self.list.last
--     if self.list.first > last then error("list is empty") end
--     local value = self.list[last]
--     self.list[last] = nil -- to allow garbage collection
--     self.list.last = last - 1
--     return value
-- end

return List
