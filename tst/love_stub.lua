-- A headless LOVE for tests that draw: enough of love.* for main.lua to load,
-- step and draw. Fonts measure text with the C64 face's real glyph advances
-- (tst/c64_metrics.lua) and every print is recorded with its box, so a test
-- can check what spilled where. Not loaded by the game.
local METRICS = dofile('tst/c64_metrics.lua')

-- ctx: whatever the test wants stamped on each text (layer, panel, button)
local Stub = { width = 1280, height = 720, texts = {}, ctx = {}, fingers = {} }

-- Anything not stubbed on purpose answers 0 and does nothing.
local function blank(fields)
    return setmetatable(fields or {}, { __index = function() return function() return 0 end end })
end

-- Font ---------------------------------------------------------------------

local function charWidth(m, ch)
    local b = ch:byte()
    if b < 32 or b > 126 then b = 63 end -- '?' for anything outside ASCII
    return m.advance[b - 31]
end

local function lineWidth(m, s)
    local w = 0
    for i = 1, #s do w = w + charWidth(m, s:sub(i, i)) end
    return w
end

local function split(text)
    local lines = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    return lines
end

-- Greedy word wrap, as LOVE does it: break at spaces, and break a word that
-- is wider than the limit on its own.
local function wrap(m, text, limit)
    local out = {}
    for _, para in ipairs(split(text)) do
        local line = ''
        for word in para:gmatch('%S+') do
            local try = line == '' and word or (line .. ' ' .. word)
            if lineWidth(m, try) <= limit then
                line = try
            else
                if line ~= '' then out[#out + 1] = line end
                line = word
                while lineWidth(m, line) > limit and #line > 1 do
                    local cut = #line - 1
                    while cut > 1 and lineWidth(m, line:sub(1, cut)) > limit do cut = cut - 1 end
                    out[#out + 1] = line:sub(1, cut)
                    line = line:sub(cut + 1)
                end
            end
        end
        out[#out + 1] = line
    end
    return out
end

local function newFont(a, b)
    local size = type(a) == 'number' and a or b or 12
    local m = METRICS[size]
    assert(m, 'no C64 metrics for size ' .. tostring(size) .. ': add it to tools/font_metrics and regenerate')
    local font = blank({ size = size })
    function font:getWidth(text)
        local w = 0
        for _, line in ipairs(split(tostring(text))) do w = math.max(w, lineWidth(m, line)) end
        return w
    end
    function font:getHeight() return m.height end
    function font:getWrap(text, limit)
        local lines = wrap(m, tostring(text), limit)
        local w = 0
        for _, l in ipairs(lines) do w = math.max(w, lineWidth(m, l)) end
        return w, lines
    end
    function font:setFilter() end
    return font
end

-- Images: real sizes from the PNG header, since sprite sheets are sliced by width.
local function pngSize(path)
    local f = io.open(path, 'rb')
    if not f then return 16, 16 end
    local head = f:read(24)
    f:close()
    local function be(i) return ((head:byte(i) * 256 + head:byte(i + 1)) * 256 + head:byte(i + 2)) * 256 + head:byte(i + 3) end
    return be(17), be(21)
end

local function newImage(path)
    local w, h = 16, 16
    if type(path) == 'string' then w, h = pngSize(path) end
    local img = blank()
    function img:getWidth() return w end
    function img:getHeight() return h end
    function img:getDimensions() return w, h end
    return img
end

-- Graphics -----------------------------------------------------------------

local g = {}
local current
local stack, tf = {}, { x = 0, y = 0, s = 1 }

local function record(text, x, y, w)
    -- x, y in the coordinates the caller drew in; tf maps them to the window
    Stub.texts[#Stub.texts + 1] = {
        text = text, x = x, y = y, w = w, h = current:getHeight(),
        tf = { x = tf.x, y = tf.y, s = tf.s }, ctx = {},
    }
    for k, v in pairs(Stub.ctx) do Stub.texts[#Stub.texts].ctx[k] = v end
end

function g.newFont(...) return newFont(...) end
function g.setFont(f) current = f end
function g.getFont() return current end
function g.newImage(p) return newImage(p) end
function g.newQuad() return blank() end
function g.newCanvas(w, h)
    local c = newImage()
    function c:getWidth() return w or 16 end
    function c:getHeight() return h or 16 end
    return c
end
function g.getDimensions() return Stub.width, Stub.height end
function g.getWidth() return Stub.width end
function g.getHeight() return Stub.height end
function g.push() stack[#stack + 1] = { x = tf.x, y = tf.y, s = tf.s } end
function g.pop() tf = table.remove(stack) or { x = 0, y = 0, s = 1 } end
function g.origin() tf = { x = 0, y = 0, s = 1 } end
function g.translate(x, y) tf.x, tf.y = tf.x + x * tf.s, tf.y + y * tf.s end
function g.scale(s) tf.s = tf.s * s end
function g.print(text, x, y)
    text = tostring(text)
    local lines = split(text)
    for i, line in ipairs(lines) do
        record(line, x or 0, (y or 0) + (i - 1) * current:getHeight(), current:getWidth(line))
    end
end
function g.printf(text, x, y, limit, align)
    local _, lines = current:getWrap(tostring(text), limit)
    for i, line in ipairs(lines) do
        local w = current:getWidth(line)
        local px = x
        if align == 'center' then px = x + (limit - w) / 2 elseif align == 'right' then px = x + limit - w end
        record(line, px, y + (i - 1) * current:getHeight(), w)
    end
end
setmetatable(g, { __index = function() return function() return 0 end end })

-- The rest of LOVE ---------------------------------------------------------

function Stub.install()
    current = newFont(11)
    love = {
        graphics = g,
        mouse = blank({ getPosition = function() return 0, 0 end, isDown = function() return false end }),
        keyboard = blank({ isDown = function() return false end }),
        touch = blank({ getTouches = function() return Stub.fingers end }),
        system = blank({ getOS = function() return 'Windows' end }),
        timer = blank({ getTime = function() return 0 end }),
        math = blank({ random = math.random }),
        filesystem = blank({ getInfo = function() return nil end, read = function() return nil end }),
        audio = blank({ newSource = function() return blank({ isPlaying = function() return false end, clone = function(s) return s end }) end }),
        window = blank({ getFullscreen = function() return false end }),
        event = blank(),
    }
end

-- Every text box in window pixels.
function Stub.boxes()
    local out = {}
    for _, t in ipairs(Stub.texts) do
        out[#out + 1] = {
            text = t.text, ctx = t.ctx,
            x1 = t.tf.x + t.x * t.tf.s, y1 = t.tf.y + t.y * t.tf.s,
            x2 = t.tf.x + (t.x + t.w) * t.tf.s, y2 = t.tf.y + (t.y + t.h) * t.tf.s,
        }
    end
    return out
end

return Stub
