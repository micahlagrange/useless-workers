-- Plays free play headless with the real game code and writes each run's
-- audit log (src/stats.lua) to stats/sim-<seed>-<player>.json, the same
-- file the game's EXPORT button writes. Set by tools/stats_sim.py:
-- SIM_SEEDS, SIM_YEARS, SIM_PLAYERS, SIM_OUT.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Stub = dofile('tst/love_stub.lua')
Stub.install()
dofile('conf.lua')
TEST_HOOKS = {}
dofile('main.lua')
local H = TEST_HOOKS.main
local Player = dofile('tools/sim_player.lua')
love.load()
love.resize(1280, 720)

local DT = 1 / 15
local written = {}
for _, player in ipairs(SIM_PLAYERS) do
    for _, seed in ipairs(SIM_SEEDS) do
        H.newGame(seed, 1)
        H.closeGoal()
        local game = H.game()
        if player ~= 'none' then Player.placeStorage(game, 8) end
        if player == 'routes' then Player.clearRoutes(game, 4) end
        local seasons = 0
        while seasons < SIM_YEARS * 4 do
            love.update(DT)
            local st = H.state()
            if st == 'report' then
                seasons = seasons + 1
                if player ~= 'none' then
                    if game.world.stock.logs >= COSTS.bin.logs then Player.placeStorage(game, 1, true) end
                    Player.placeStorage(game, 3)
                end
                if player == 'routes' then Player.clearRoutes(game, 4) end
                love.keypressed('return')
            elseif st == 'annual' then
                game.scoring:startEndless(); H.setState('playing')
            elseif st == 'gameover' then
                break
            end
        end
        local path = SIM_OUT .. '/sim-' .. seed .. '-' .. player .. '.json'
        local f = assert(io.open(path, 'w'))
        f:write(game.stats:export('headless sim, player: ' .. player, { player = player, years = SIM_YEARS, endedAs = H.state() }))
        f:close()
        written[#written + 1] = path
    end
end
SIM_WRITTEN = written
