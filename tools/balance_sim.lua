-- Plays free play with the real game code (five seeds, three years, Mild
-- wilds) and reports per season: fed,
-- hunger, hardships by reason, departures, migrants, and how each role
-- spends its time.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Worker = require('src.worker')
love.load()
love.resize(1280, 720)

local reasons = {}
local complain = Worker.complain
function Worker:complain(reason, node)
    reasons[#reasons + 1] = { role = self.role, reason = reason }
    return complain(self, reason, node)
end
local quits = {}
local quit = Worker.quit
function Worker:quit(reason)
    quits[#quits + 1] = { role = self.role, reason = reason or 'starved' }
    return quit(self, reason)
end

local function bucket(w)
    local s, g = w.state, w.goal
    if s == 'working' or (s == 'walking' and (g == 'work' or g == 'deliver')) then return 'work' end
    if s == 'eating' or (s == 'walking' and (g == 'eat' or g == 'fetch')) then return 'food' end
    if s == 'breaking' or (s == 'walking' and g == 'break') then return 'rest' end
    if s == 'sulking' then return 'sulk' end
    if s == 'quitting' then return 'leaving' end
    return 'idle'
end

local function placeStorage(game, n, bin)
    local w, ab = game.world, game.abilities
    local br = w.breakroom
    local placed = 0
    ab:select(bin and ABILITY_BIN or ABILITY_STORAGE)
    for r = 2, 8 do
        for dy = -r, r do
            for dx = -r, r do
                if placed >= n then return placed end
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = br.x + dx, br.y + dy
                    if w:isReachable(x, y) and w:canSite(bin and SITE_BIN or SITE_STORAGE, x, y) and ab:use(x, y) then placed = placed + 1 end
                end
            end
        end
    end
    return placed
end

-- The route clearer: each season, for the nearest few things out of reach
-- (bushes, trees, ore), the cheapest way through: grass is free, stone is
-- mined, water bridged while the logs last.
local function clearRoutes(game, n)
    local w, ab = game.world, game.abilities
    local reach = w:reachableFromBreakroom()
    local INF = math.huge
    local dist, prev = {}, {}
    local heap = {}
    local function key(x, y) return y * 1000 + x end
    local function push(d, x, y)
        heap[#heap + 1] = { d, x, y }
        local i = #heap
        while i > 1 and heap[math.floor(i / 2)][1] > heap[i][1] do
            heap[i], heap[math.floor(i / 2)] = heap[math.floor(i / 2)], heap[i]; i = math.floor(i / 2)
        end
    end
    local function pop()
        local top = heap[1]; heap[1] = heap[#heap]; heap[#heap] = nil
        local i = 1
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            if heap[l] and heap[l][1] < heap[m][1] then m = l end
            if heap[r] and heap[r][1] < heap[m][1] then m = r end
            if m == i then break end
            heap[i], heap[m] = heap[m], heap[i]; i = m
        end
        return top
    end
    for x = 1, w.w do for y = 1, w.h do
        if reach[x][y] then dist[key(x, y)] = 0; push(0, x, y) end
    end end
    local function cost(t)
        if t.passable then return 1 end
        if t.type == TILE_STONE or t.type == TILE_SNOW then return 4 end
        if t.type == TILE_WATER then return 6 end
        return nil
    end
    while #heap > 0 do
        local d, x, y = table.unpack(pop())
        if d <= (dist[key(x, y)] or INF) then
            for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
                local t = w:get(c[1], c[2])
                local k = t and cost(t)
                if k then
                    local nd = d + k
                    if nd < (dist[key(c[1], c[2])] or INF) then
                        dist[key(c[1], c[2])] = nd; prev[key(c[1], c[2])] = { x, y }; push(nd, c[1], c[2])
                    end
                end
            end
        end
    end
    local targets = {}
    for _, node in ipairs(w.nodes) do
        if not w:nodeReachable(node) and dist[key(node.x, node.y)] then
            targets[#targets + 1] = { node = node, d = dist[key(node.x, node.y)] }
        end
    end
    -- food first, like a sensible player, then whatever is nearest
    table.sort(targets, function(a, b)
        local fa, fb = a.node.kind == NODE_BUSH, b.node.kind == NODE_BUSH
        if fa ~= fb then return fa end
        return a.d < b.d
    end)
    local opened = 0
    for _, tg in ipairs(targets) do
        if opened >= n then break end
        local x, y = tg.node.x, tg.node.y
        local p = prev[key(x, y)]
        while p do
            local t = w:get(p[1], p[2])
            if t.type == TILE_STONE or t.type == TILE_SNOW then
                ab:select(ABILITY_MINE); ab:designateMine(p[1], p[2], p[1], p[2])
            elseif t.type == TILE_WATER and not t.site then
                ab:select(ABILITY_BRIDGE); ab:useLine(p[1], p[2], p[1], p[2])
            end
            p = prev[key(p[1], p[2])]
        end
        opened = opened + 1
    end
end

local DT = 1 / 15
local seeds = { 'PUPPER', 'FROG', 'MOSS', 'ACORN', 'RIVER' }
local years = 3
for _, diff in ipairs({ 1 }) do
  for _, player in ipairs({ 'none', 'storage', 'routes' }) do
    local rows = {}
    for _, seed in ipairs(seeds) do
      reasons, quits = {}, {}
      H.newGame(seed, diff)
      H.closeGoal()
      local game = H.game()
      if player ~= 'none' then placeStorage(game, 8) end
      if player == 'routes' then clearRoutes(game, 4) end
      local q = 1
      local acc = { roles = {}, hungry = 0, samples = 0 }
      local t = 0
      local function season()
        local r = rows[q] or { fed = 0, n = 0, hard = {}, quits = 0, hires = 0, staff = 0, roles = {}, hungry = 0, samples = 0 }
        rows[q] = r
        return r
      end
      while q <= years * 4 do
        love.update(DT)
        t = t + DT
        if t >= 1 then
          t = t - 1
          local r = season()
          for _, w in ipairs(game.workers) do
            if w.alive then
              local rr = r.roles[w.role] or { work = 0, food = 0, rest = 0, sulk = 0, idle = 0, leaving = 0, n = 0, hungry = 0 }
              r.roles[w.role] = rr
              local b = bucket(w)
              rr[b] = rr[b] + 1
              rr.n = rr.n + 1
              if w.hunger < HUNGER_EAT_THRESHOLD then rr.hungry = rr.hungry + 1 end
            end
          end
        end
        local st = H.state()
        if st == 'report' then
          local rep = game.report
          local r = season()
          r.fed = r.fed + rep.fedPct; r.n = r.n + 1
          r.quits = r.quits + rep.attrition; r.hires = r.hires + rep.hires
          for _, c in ipairs(reasons) do r.hard[c.role .. ':' .. c.reason] = (r.hard[c.role .. ':' .. c.reason] or 0) + 1 end
          reasons = {}
          local alive = 0 for _, w in ipairs(game.workers) do if w.alive then alive = alive + 1 end end
          r.staff = r.staff + alive
          q = q + 1
          if player ~= 'none' then
            if game.world.stock.logs >= COSTS.bin.logs then placeStorage(game, 1, true) end
            placeStorage(game, 3)
          end
          if player == 'routes' then clearRoutes(game, 4) end
          love.keypressed('return')
        elseif st == 'annual' then
          game.scoring:startEndless(); H.setState('playing')
        elseif st == 'gameover' then
          for qq = q, years * 4 do local r = season(); r.n = r.n + 1; r.gone = (r.gone or 0) + 1 end
          break
        end
      end
    end
    print(string.format('\n=== %s, player: %s (%d seeds) ===', DIFFICULTIES[diff].name, player, #seeds))
    print('season   fed%  staff  left  arrived  hardships (role:reason)            role time: work/food/rest/idle/sulk %, hungry %')
    print('(staff is the average band size per seed; left, arrived and hardships are totals over the seeds)')
    for i, r in ipairs(rows) do
      local hard = {}
      for k, v in pairs(r.hard) do hard[#hard + 1] = k .. '=' .. v end
      table.sort(hard)
      local rl = {}
      for _, role in ipairs({ 'forager', 'lumberjack', 'miner' }) do
        local x = r.roles[role]
        if x and x.n > 0 then
          local p = function(k) return math.floor(100 * x[k] / x.n + 0.5) end
          rl[#rl + 1] = string.format('%s %d/%d/%d/%d/%d h%d', role:sub(1, 3), p('work'), p('food'), p('rest'), p('idle'), p('sulk'), p('hungry'))
        end
      end
      local n = math.max(1, r.n)
      print(string.format('%-8s %4d  %5.1f  %4d  %7d  %-36s %s%s', ('Y' .. math.floor((i - 1) / 4) + 1 .. ' ' .. SEASON_NAMES[(i - 1) % 4 + 1]), math.floor(r.fed / math.max(1, r.n - (r.gone or 0))), r.staff / n, r.quits, r.hires,
        table.concat(hard, ' '), table.concat(rl, '  '), r.gone and ('  [' .. r.gone .. ' band(s) gone]') or ''))
    end
  end
end
