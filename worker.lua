module('worker')

local spriteshet = require('spritesheet')

Worker = {}
function Worker:new(x, y, obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    obj.x = x
    obj.y = y
end