-- What the bunch says: every say() is kept here with who said it, where and
-- when, for the Chatter panel, its unread badge and a morphi's Lately lines.
-- Also the pure parts of the speech bubbles (wrapping and placement), so the
-- tests can check them without drawing.
require('src.constants')

local Chatter = {}
Chatter.__index = Chatter

Chatter.KEEP = 60
Chatter.MAX_LINES = 3
Chatter.MIN_SHOW = 1.4 -- seconds of real time a bubble stays, whatever the game speed

function Chatter.new()
    local self = setmetatable({}, Chatter)
    self.lines = {}
    self.unread = 0
    self.open = false
    self.seq = 0
    return self
end

-- A few lines so the panel is not empty on day one.
function Chatter:seed(names, t)
    local starts = { 'what a nice meadow', 'is that a shiny?', 'first one to the stash wins' }
    for i, text in ipairs(starts) do
        if names[i] then self:add({ name = names[i] }, text, 'by the home nest', t or 0, true) end
    end
end

-- One line said. quiet: does not count as unread (the starting lines).
function Chatter:add(speaker, text, where, t, quiet)
    self.seq = self.seq + 1
    local e = {
        id = self.seq, speaker = speaker, name = speaker.name or '?', text = text,
        where = where or 'in the meadow', t = t or 0,
    }
    self.lines[#self.lines + 1] = e
    while #self.lines > Chatter.KEEP do table.remove(self.lines, 1) end
    if not self.open and not quiet then self.unread = self.unread + 1 end
    return e
end

function Chatter:setOpen(open)
    self.open = open
    if open then self.unread = 0 end
end

-- The badge: nothing, a count, or 9+.
function Chatter:badge()
    if self.unread <= 0 then return nil end
    return self.unread > 9 and '9+' or tostring(self.unread)
end

-- A speaker's last n lines, oldest first.
function Chatter:lately(speaker, n)
    n = n or 2
    local out = {}
    for i = #self.lines, 1, -1 do
        if self.lines[i].speaker == speaker then
            table.insert(out, 1, self.lines[i].text)
            if #out >= n then break end
        end
    end
    return out
end

-- "just now", "20 s ago", "2 min ago" (game seconds).
function Chatter.ago(dt)
    dt = math.max(0, dt or 0)
    if dt < 10 then return 'just now' end
    if dt < 60 then return (math.floor(dt / 10) * 10) .. ' s ago' end
    return math.floor(dt / 60) .. ' min ago'
end

-- Where a morphi is, in meadow words. world may be nil (tests, menus).
function Chatter.whereOf(worker, world)
    if not world or not worker.tile then return 'in the meadow' end
    local p = worker:tile()
    local t = world:get(p.x, p.y)
    if not t then return 'in the meadow' end
    if t.type == TILE_BREAKROOM then return 'by the home nest' end
    if t.bed or t.type == 'bed' or worker.state == 'breaking' then return 'in the nest' end
    if t.type == TILE_STONE or t.type == TILE_DIRT then return 'on the clay' end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local n = world:get(p.x + d[1], p.y + d[2])
        if t.type == TILE_WATER or (n and n.type == TILE_WATER) then return 'at the stream' end
    end
    return 'in the meadow'
end

-- Word wrap to at most maxLines lines of maxW, measured by width(text). A
-- word too long for a line is cut by characters; text past the last line
-- ends in "..", so nothing is ever drawn past the plate.
function Chatter.wrap(text, maxW, width, maxLines)
    maxLines = maxLines or Chatter.MAX_LINES
    local lines, cur = {}, ''
    local function push(s)
        lines[#lines + 1] = s
    end
    for word in tostring(text):gmatch('%S+') do
        local try = cur == '' and word or (cur .. ' ' .. word)
        if width(try) <= maxW then
            cur = try
        else
            if cur ~= '' then push(cur) end
            cur = word
            while width(cur) > maxW and #cur > 1 do
                local cut = #cur - 1
                while cut > 1 and width(cur:sub(1, cut)) > maxW do cut = cut - 1 end
                push(cur:sub(1, cut))
                cur = cur:sub(cut + 1)
            end
        end
    end
    if cur ~= '' then push(cur) end
    if #lines > maxLines then
        local last = lines[maxLines]
        while #last > 0 and width(last .. '..') > maxW do last = last:sub(1, -2) end
        lines[maxLines] = last .. '..'
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    end
    if #lines == 0 then lines[1] = '' end
    return lines
end

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Place bubbles. Each bubble is {sx, sy (the speaker's head on screen), w,
-- h, t (when said), speakerX, speakerY}. Newest first wins its spot. Two
-- speakers standing close together (a pair talking) show only the newer
-- bubble. Bubbles move up, then below the speaker, then sideways to avoid
-- each other and the blocked rects, and are kept inside the screen box
-- {x, y, w, h}. Sets b.x, b.y, b.below, b.hidden.
function Chatter.place(bubbles, blocked, screen, pairDist)
    pairDist = pairDist or 14
    table.sort(bubbles, function(a, b) return (a.t or 0) > (b.t or 0) end)
    local placed = {}
    for _, r in ipairs(blocked or {}) do placed[#placed + 1] = r end
    local shown = {}
    for _, b in ipairs(bubbles) do
        b.hidden = false
        for _, s in ipairs(shown) do
            local dx, dy = (b.speakerX or b.sx) - (s.speakerX or s.sx), (b.speakerY or b.sy) - (s.speakerY or s.sy)
            if dx * dx + dy * dy <= pairDist * pairDist then b.hidden = true; break end
        end
        if not b.hidden then
            local function fits(x, y)
                local r = { x = x, y = y, w = b.w, h = b.h }
                if x < screen.x or y < screen.y or x + b.w > screen.x + screen.w or y + b.h > screen.y + screen.h then return false end
                for _, o in ipairs(placed) do if overlaps(r, o) then return false end end
                return true
            end
            local function clampX(x) return math.max(screen.x, math.min(x, screen.x + screen.w - b.w)) end
            local tries = {}
            local x0 = clampX(b.sx - b.w / 2)
            for k = 0, 6 do tries[#tries + 1] = { x0, b.sy - 10 - b.h - k * (b.h * 0.5 + 4), false } end
            for k = 0, 3 do tries[#tries + 1] = { x0, b.sy + 30 + k * (b.h * 0.5 + 4), true } end
            for _, side in ipairs({ -1, 1 }) do
                for k = 1, 3 do tries[#tries + 1] = { clampX(x0 + side * k * (b.w * 0.6)), b.sy - 10 - b.h, false } end
            end
            local spot
            for _, tr in ipairs(tries) do
                if fits(tr[1], tr[2]) then spot = tr; break end
            end
            if spot then
                b.x, b.y, b.below = spot[1], spot[2], spot[3]
                placed[#placed + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
                shown[#shown + 1] = b
            else
                b.hidden = true -- nowhere free: it waits in the Chatter log
            end
        end
    end
    return bubbles
end

return Chatter
