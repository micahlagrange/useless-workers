local object      = require('libs.classic')
local spritesheet = require('src.drawing.spritesheet')
local food        = require('src.needs.food')
local GameObjects = require('src.system.gameobjects')

local uiElements  = {}
local guiElement  = object:extend()
local arrow       = guiElement:extend()
local mouseDownOn = nil

UI                = {}


function arrow:setMouseDownOn(val)
    if val == true then
        self.mouseDownOn = true
    else
        self.mouseDownOn = false
    end
end

function arrow:new(facing)
    self.x, self.y          = -99, -99
    self.mouseDownOn        = false
    self.width, self.height = 32, 32

    self.spriteSheet        = love.graphics.newImage('spritesheets/page_arrow.png')
    self.arrowGrid          = spritesheet.NewAnim8Grid(self.spriteSheet, 32, 32)
    self.arrowIdleAnim      = Anim8.newAnimation(self.arrowGrid('1-1', 1), 1)
    self.arrowClickedAnim   = Anim8.newAnimation(self.arrowGrid('2-2', 1), 1)
    self.facing             = facing
    self.scaleX             = 1
    self.scaleY             = 1
    self.currentAnimation   = self.arrowIdleAnim
end

function arrow:draw()
    local windowWidth, windowHeight = love.window.getMode()
    local middleOfWindowY = windowHeight / 2
    local nextX, nextY = windowWidth, middleOfWindowY
    local prevX, prevY = 0, middleOfWindowY

    if self.facing == LEFT then
        self.scaleX = -1
        self.x = prevX + self.width
        self.y = prevY
    else
        self.x = nextX - self.width
        self.y = nextY
    end
    local cx, cy = Camera:cameraCoords(self.x, self.y)

    self.currentAnimation:draw(
        self.spriteSheet,
        self.x,
        self.y,
        0,
        self.scaleX,
        self.scaleY)
end

local function cleanEatenFood()
    local toClean = {}
    for i, f in ipairs(GameObjects.get_all_objects()) do
        if type(f) == "food" and f.eaten then
            table.insert(toClean, i)
        end
    end

    for idx, _ in ipairs(toClean) do
        GameObjects.remove(idx)
    end
end

local function addRandomFood(x, y)
    GameObjects.add(food(x, y))
    cleanEatenFood()
end

local function getClickedUIElement(mouseX, mouseY)
    -- Check if mouse x,y is in the shape of each ui element
    -- https://love2d.org/wiki/Shape:testPoint
    return false
end

function UI.mouseDown(mouseX, mouseY, button, x, y)
    local uiElement = getClickedUIElement(mouseX, mouseY)
    if uiElement then
        mouseDownOn = uiElement
        uiElement:setMouseDownOn(true)
    else
        mouseDownOn = nil
    end
end

function UI.mouseUp(mouseX, mouseY, button, x, y)
    -- mousePointer is the windfield collision rect you can use to detect what the mouse clicked on if you need to
    if button == INPUT.Mouse.LMB then
        local uiElement = getClickedUIElement(mouseX, mouseY)
        if uiElement then
            if mouseDownOn == uiElement then uiElement:click() end
        else
            if mouseDownOn == nil then
                addRandomFood(x, y)
            end
        end
    end

    UI.unclick_all()
end

function UI.unclick_all()
    for _, e in pairs(uiElements) do
        e:setMouseDownOn(false)
    end
end

function UI.update_all_ui_elements()
    for _, e in pairs(uiElements) do
        e:update()
    end
end

function UI.draw_all_ui_elements()
    --draw next page and previous page buttons
    for _, e in pairs(uiElements) do
        e:draw()
    end
end

-- create ui elements before return
table.insert(uiElements, arrow(RIGHT))
table.insert(uiElements, arrow(LEFT))

return UI
