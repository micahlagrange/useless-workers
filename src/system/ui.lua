local object      = require('libs.classic')
local spritesheet = require('src.drawing.spritesheet')
local food        = require('src.needs.food')
local GameObjects = require('src.system.gameobjects')

local uiElements  = {}
local guielement  = object:extend()
local mouseDownOn = nil

-- Create a world for the physics objects to exist in
local camX, camY  = Camera:position()
local UI          = {}

UIDebugText       = ""
local function beginContact(a, b, coll)
    local x, y = coll:getNormal()
    UIDebugText = UIDebugText ..
        "\n" ..
        a:getUserData() .. " colliding with " .. b:getUserData() .. " with a vector normal of: " .. x .. ", " .. y
    exit()
end
local function endContact() end
local function preSolve() end
local function postSolve() end

function guielement:new(name, facing, sheet)
    self.name               = name or 'guielement'
    self.facing             = facing or RIGHT
    self.x, self.y          = -999, -999
    self.mouseDownOn        = false
    self.width, self.height = 32, 32

    self.spriteSheet        = love.graphics.newImage(sheet)
    self.arrowGrid          = spritesheet.NewAnim8Grid(self.spriteSheet, 32, 32)
    self.idleAnim           = Anim8.newAnimation(self.arrowGrid('1-1', 1), 1)
    self.clickedAnim        = Anim8.newAnimation(self.arrowGrid('2-2', 1), 1)
    self.scaleX             = 1
    self.scaleY             = 1
    self.currentAnimation   = self.idleAnim
    self.fixture            = UI.CreateShape(self.x, self.y, self.width, self.height)
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

function UI.printDebugPoints(fixture)
    local body = fixture:getBody()
    local shape = fixture:getShape()
    -- assumes square shape
    local x1, y1, x2, y2, x3, y3, x4, y4 = body:getWorldPoints(shape:getPoints())

    love.graphics.print("L:" .. x1 .. ", " .. y1, x1, y1 - 15)

    love.graphics.print("L:" .. x2 .. ", " .. y2, x2, y2)

    love.graphics.print("L:" .. x3 .. ", " .. y3, x3, y3 + 15)

    love.graphics.print("L:" .. x4 .. ", " .. y4, x4, y4 + 30)
end

function UI.printDebugNearFixture(fixture)
    local body = fixture:getBody()
    local shape = fixture:getShape()
    local worldX, worldY = body:getPosition()
    local localX, localY = body:getLocalPoints(shape:getPoints())
    -- Draw the world and local coordinates
    love.graphics.setColor(0, 1, 0)
    love.graphics.print("W:" .. worldX .. ", " .. worldY, worldX, worldY)
    love.graphics.print("L:" .. localX .. ", " .. localY, worldX, worldY + 15)
    love.graphics.setColor(1, 1, 1)
end

function UI.debugDrawFixture(fixture)
    local body = fixture:getBody()
    local shape = fixture:getShape()
    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
    UI.printDebugPoints(fixture)
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
        if shape:testPoint(bx, by, body:getAngle(), lx, ly) then
            return guielement
        end
    end
    return false
end

function UI.mouseDown(mouseX, mouseY, button)
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

function UI.draw_all_ui_elements(debug)
    --draw next page and previous page buttons
    for _, e in pairs(uiElements) do
        e:draw()
        if debug == true then
            UI.debugDrawFixture(e.fixture)
        end
    end

    if debug then
        love.graphics.print(UIDebugText, 500, 500)
    end
end

-- create ui elements before return
table.insert(uiElements, guielement('nextarrow', RIGHT, 'spritesheets/page_arrow.png'))
table.insert(uiElements, guielement('previousarrow', LEFT, 'spritesheets/page_arrow.png'))

return UI
