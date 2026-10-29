-- How a little blob moves and looks on top of its sprite: the hop as it
-- walks, blinks, a moving mouth while it talks, squash on a bump, a happy
-- wiggle, a wave. Pure maths on the worker and the game clock, so the tests
-- can step it; both tile looks draw from the pose it returns.
--
-- Less motion (Feel.calm) keeps the faces and the wave but drops the hops,
-- squash, wiggles and pulsing. Remembered in the save folder.
local Feel = {}

Feel.FILE = 'calm.txt'
Feel.calm = false

-- How long each effect lasts, in game seconds (the mockup's timings).
Feel.BUMP_TIME = 0.6
Feel.HAPPY_TIME = 1.2
Feel.WAVE_TIME = 1.2
Feel.BLINK_EVERY = 3.7
Feel.BLINK_TIME = 0.12
Feel.STEP_TIME = 0.24

function Feel.setCalm(on)
    Feel.calm = on and true or false
    if love and love.filesystem and love.filesystem.write then
        pcall(love.filesystem.write, Feel.FILE, Feel.calm and 'on' or 'off')
    end
    return Feel.calm
end

function Feel.toggleCalm() return Feel.setCalm(not Feel.calm) end

function Feel.load()
    if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(Feel.FILE)) then return end
    local ok, data = pcall(love.filesystem.read, Feel.FILE)
    if ok and type(data) == 'string' then Feel.calm = data:match('on') ~= nil end
end

-- Start an effect ('bump', 'happy' or 'wave') on a worker now.
function Feel.start(w, kind, clock)
    w.fx = w.fx or {}
    w.fx[kind] = clock or w.clock or 0
end

-- Seconds into an effect, or nil when it is not playing.
function Feel.age(w, kind, clock, length)
    local t0 = w.fx and w.fx[kind]
    if not t0 then return nil end
    local t = clock - t0
    if t < 0 or t >= length then return nil end
    return t
end

-- The pose this frame: hop (px up), sx/sy (squash), rot (radians), and the
-- face: blink, eyesShut, happy, talking, mouthOpen, lookDown, wave (the
-- arm's angle, or nil).
function Feel.pose(w, clock, selected)
    clock = clock or 0
    local calm = Feel.calm
    local id = w.id or 0
    local p = { hop = 0, sx = 1, sy = 1, rot = 0 }
    local running = (w.speed or 0) > (WORKER_SPEED or 1e9) * 1.15
    if w.moving and not calm then
        local step = running and Feel.STEP_TIME * 0.7 or Feel.STEP_TIME
        p.hop = math.abs(math.sin((w.animTime or 0) * math.pi / step)) * (running and 2.5 or 1.5)
    elseif not w.moving and not calm then
        -- standing about, a little blob breathes
        p.sy = 1 + 0.06 * math.sin(clock * 4 + id * 1.7)
    end
    local tb = Feel.age(w, 'bump', clock, Feel.BUMP_TIME)
    if tb and not calm then
        local q = 0.2 * math.exp(-tb * 7) * math.cos(tb * 24)
        p.sx, p.sy = p.sx * (1 + q), p.sy * (1 - q)
    end
    local th = Feel.age(w, 'happy', clock, Feel.HAPPY_TIME)
    p.happy = th ~= nil
    if th and not calm then p.rot = 0.2 * math.exp(-th * 3) * math.sin(th * 24) end
    local tv = Feel.age(w, 'wave', clock, Feel.WAVE_TIME)
    if tv then p.wave = -0.6 + (calm and 0 or math.sin(tv * 16) * 0.55) end
    p.sleeping = w.state == 'breaking'
    if p.sleeping then p.hop = 0; p.sy = p.sy * 0.9; p.sx = p.sx * 1.06 end
    p.blink = ((clock + id * 1.3) % Feel.BLINK_EVERY) < Feel.BLINK_TIME
    p.eyesShut = p.sleeping or p.blink
    p.talking = w.bubble ~= nil and not p.sleeping
    p.mouthOpen = p.talking and math.sin(clock * 11 + id) > 0
    p.lookDown = selected and true or false
    p.shadow = math.max(0.5, 1 - p.hop / 8)
    return p
end

-- Where the eyes are on each frame of a 16 px sheet: the first row from the
-- top with two lone dark pixels. Returns { [frame] = { {x, y, r, g, b}, ... } }
-- with the colour of the skin just above each eye, for painting a lid.
function Feel.findEyes(data, frames, size)
    size = size or 16
    local eyes = {}
    for f = 1, frames do
        local ox = (f - 1) * size
        local function dark(x, y)
            local r, g, b, a = data:getPixel(ox + x, y)
            return a > 0 and r + g + b < 0.6
        end
        for y = 1, size - 2 do
            local row = {}
            for x = 1, size - 2 do
                if dark(x, y) and not dark(x - 1, y) and not dark(x + 1, y) then
                    local r, g, b = data:getPixel(ox + x, y - 1)
                    row[#row + 1] = { x = x, y = y, r = r, g = g, b = b }
                end
            end
            if #row == 2 then eyes[f] = row; break end
        end
    end
    return eyes
end

return Feel
