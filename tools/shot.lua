-- Desktop screenshots for development: plays the real game in a window and
-- saves PNGs, without a web build. Run from the repo root:
--   "C:/Program Files/LOVE/lovec.exe" . --shot path/to/steps.lua [outdir]
-- conf.lua sees --shot and turns on TEST_HOOKS; main.lua loads this file.
-- A steps file is plain Lua run as a coroutine with these helpers:
--   H                     TEST_HOOKS.main (game(), ui(), newGame, ...)
--   size(w, h)            resize the window
--   wait(seconds)         let the game run
--   frames(n)             let n frames pass
--   click(x, y[, button]) press and release at a window point
--   press(x, y) / release(x, y) / move(x, y)
--   drag({ {x, y}, ... }) press at the first point, move through, release
--   key(k)                a key press
--   shot(name)            save <outdir>/<name>.png
--   tile(tx, ty)          the window point at a tile's centre
--   say(...)              print to the console
local outdir = SHOT_OUT or 'shots'
local H = TEST_HOOKS.main
local env = setmetatable({ H = H }, { __index = _G })
local co
local waitUntil, waitFrames = 0, 0
local now = 0

function env.say(...) print(...) end
function env.wait(s) waitUntil = now + s coroutine.yield() end
function env.frames(n) waitFrames = n coroutine.yield() end
function env.size(w, h)
    love.window.setMode(w, h, { resizable = true, vsync = 1 })
    love.resize(w, h)
    env.frames(2)
end
function env.move(x, y) love.mousemoved(x, y, 0, 0, false) end
function env.press(x, y, b) love.mousemoved(x, y, 0, 0, false) love.mousepressed(x, y, b or 1, false) end
function env.release(x, y, b) love.mousereleased(x, y, b or 1, false) end
function env.click(x, y, b) env.press(x, y, b) env.frames(1) env.release(x, y, b) env.frames(2) end
function env.drag(pts)
    local lx, ly = pts[1][1], pts[1][2]
    env.press(lx, ly)
    env.frames(1)
    for i = 2, #pts do
        local x, y = pts[i][1], pts[i][2]
        love.mousemoved(x, y, x - lx, y - ly, false)
        lx, ly = x, y
        env.frames(1)
    end
    env.release(lx, ly)
    env.frames(2)
end
function env.key(k) love.keypressed(k, k, false) env.frames(2) end
function env.tile(tx, ty)
    local g = H.game()
    local p = g.camera:toScreen((tx - 0.5) * TILE_SIZE, (ty - 0.5) * TILE_SIZE)
    return p.x, p.y
end
function env.shot(name)
    love.graphics.captureScreenshot(function(img)
        local data = img:encode('png')
        local f = assert(io.open(outdir .. '/' .. name .. '.png', 'wb'))
        f:write(data:getString())
        f:close()
        print('shot ' .. outdir .. '/' .. name .. '.png')
    end)
    env.frames(2)
end

local chunk = assert(loadfile(SHOT_SCRIPT))
setfenv(chunk, env)
co = coroutine.create(chunk)

local update = love.update
function love.update(dt)
    now = now + dt
    update(dt)
    if waitFrames > 0 then waitFrames = waitFrames - 1 return end
    if now < waitUntil then return end
    if coroutine.status(co) == 'suspended' then
        local ok, err = coroutine.resume(co)
        if not ok then print('shot script error: ' .. tostring(err)) love.event.quit(1) end
    elseif coroutine.status(co) == 'dead' then
        love.event.quit()
    end
end
