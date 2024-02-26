local open = io.open
local loveMock = {}

local ImageMock = {}
function ImageMock:getWidth()
end
function ImageMock:getHeight()
end

local function newImageMock()
    return ImageMock
end

local function newQuadMock()

end

local function newSpriteBatchMock()
end

local function readMock(path)
    local file = open(path, "rb")  -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local LoveMock = {}
function LoveMock:new()
    local obj = loveMock
    setmetatable(self, obj)
    self.__index = self
    self.filesystem = {}
    self.graphics = {}
    self.filesystem.read = readMock
    self.graphics.newImage = newImageMock
    self.graphics.newSpriteBatch = newSpriteBatchMock
    self.graphics.newQuad = newQuadMock
    return self
end

LoveMock:new() -- why this works, i do not know. but don't remove this line
return LoveMock
