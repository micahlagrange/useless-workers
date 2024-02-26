local ldtkparser = require('src.collision')
local inspect = require('libs.inspect')

ldtkparser:new()
ldtkparser:loadJSON()
for _,i in ipairs(ldtkparser:findIntGrid()) do
        print(inspect(i))
end
