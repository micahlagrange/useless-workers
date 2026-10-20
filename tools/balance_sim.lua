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

local Player = dofile('tools/sim_player.lua')
local placeStorage, clearRoutes = Player.placeStorage, Player.clearRoutes

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
