-- local physics = require("love.physics")
local object      = require('libs.classic')
local spritesheet = require('src.drawing.spritesheet')
local food        = require('src.needs.food')
local GameObjects = require('src.system.gameobjects')

local uiElements  = {}
local guielement  = object:extend()
local mouseDownOn = nil

-- Create a world for the physics objects to exist in
local uiworld     = love.physics.newWorld(0, 0, true)
local UI          = {}

local function createUIShape(x, y, w, h)
    -- Create a body in the world at position (100, 100)
    local body = love.physics.newBody(uiworld, x, y, "static")

    -- Create a rectangle shape associated with the body
    local shape = love.physics.newRectangleShape(w, h)

    local fixture = love.physics.newFixture(body, shape)
    fixture:setSensor(true)
    return fixture
end


function guielement:new(name, facing, spriteSheet)
    self.name               = name or 'guielement'
    self.facing             = facing or RIGHT
    self.x, self.y          = -999, -999
    self.mouseDownOn        = false
    self.width, self.height = 32, 32

    self.spriteSheet        = love.graphics.newImage(spriteSheet)
    self.arrowGrid          = spritesheet.NewAnim8Grid(self.spriteSheet, 32, 32)
    self.idleAnim           = Anim8.newAnimation(self.arrowGrid('1-1', 1), 1)
    self.clickedAnim        = Anim8.newAnimation(self.arrowGrid('2-2', 1), 1)
    self.scaleX             = 1
    self.scaleY             = 1
    self.currentAnimation   = self.idleAnim
    self.fixture            = createUIShape(self.x, self.y, self.width, self.height)
end

function guielement:setMouseDownOn(val)
    if val == true then
        self.mouseDownOn = true
    else
        self.mouseDownOn = false
    end
end

function guielement:click()
    print(self.name, ' do be clicked!')
end

function guielement:draw()
    local windowWidth, windowHeight = love.window.getMode()
    local middleOfWindowY = windowHeight / 2
    local nextX, nextY = windowWidth, middleOfWindowY
    local prevX, prevY = 0, middleOfWindowY

    if self.mouseDownOn then
        self.currentAnimation = self.clickedAnim
    else
        self.currentAnimation = self.idleAnim
    end
    if self.facing == LEFT then
        self.scaleX = -1
        self.x = prevX + self.width
        self.y = prevY
        self.fixture:getBody():setPosition(self.x - self.width / 2, self.y + self.height / 2)
    else
        self.x = nextX - self.width
        self.y = nextY
        self.fixture:getBody():setPosition(self.x + self.width / 2, self.y + self.height / 2)
    end

    self.currentAnimation:draw(
        self.spriteSheet,
        self.x,
        self.y,
        0,
        self.scaleX,
        self.scaleY)
end

function guielement:debug()
    local body = self.fixture:getBody()
    local shape = self.fixture:getShape()
    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
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
    -- returns clicked element or false
    -- https://love2d.org/wiki/Shape:testPoint
    for _, guielement in ipairs(uiElements) do
        local fixture = guielement.fixture
        local body = fixture:getBody()
        local shape = fixture:getShape()
        -- Transform the point from world coordinates to local coordinates
        -- local lx, ly = body:getLocalPoint(mouseX, mouseY)
        local lx, ly = mouseX, mouseY
        -- Check if the point is inside the shape
        local bx, by = Camera:worldCoords(body:getPosition()) -- this works but i want to fix it "better" by setting the world coords relative to the camera at guiworld creation time!
        -- local bx, by = body:getPosition()
        print("clicked:", lx, ly, "\n\t\tbody at ", bx, by)
        if shape:testPoint(bx, by, body:getAngle(), lx, ly) then
            print("Mouse clicked inside the physics object!")
            return guielement
        end
    end
    return false
end

function UI.mouseDown(mouseX, mouseY, button, x, y)
    print('mouseDown')
    local uiElement = getClickedUIElement(mouseX, mouseY)
    if uiElement then
        mouseDownOn = uiElement
        uiElement:setMouseDownOn(true)
    else
        mouseDownOn = nil
    end
end

function UI.mouseUp(mouseX, mouseY, button, x, y)
    print('mouseUp')
    -- mousePointer is the windfield collision rect you can use to detect what the mouse clicked on if you need to
    if button == INPUT.Mouse.LMB then
        local uiElement = getClickedUIElement(mouseX, mouseY)
        if uiElement then
            if mouseDownOn == uiElement then uiElement:click() end
        else
            if mouseDownOn == nil then
                -- addRandomFood(x, y)
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

function UI.draw_all_ui_elements(debug)
    --draw next page and previous page buttons
    for _, e in pairs(uiElements) do
        e:draw()
        if debug == true then
            e:debug()
        end
    end
end

-- create ui elements before return
table.insert(uiElements, guielement('nextarrow', RIGHT, 'spritesheets/page_arrow.png'))
table.insert(uiElements, guielement('previousarrow', LEFT, 'spritesheets/page_arrow.png'))

return UI
