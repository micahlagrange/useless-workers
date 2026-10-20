#!/usr/bin/env python3
"""Free play audit logs without playing: runs the real game code headless
for some seeds and years with a simple player and writes each run's stats
JSON (the same file the in-game EXPORT writes) into stats/.

    python tools/stats_sim.py                      # 3 seeds, 3 years, 'routes' player
    python tools/stats_sim.py --seeds FROG MOSS --years 5 --players none storage routes

Then: python tools/stats_report.py stats/sim-FROG-routes.json
Needs lupa, like the tests.
"""
import argparse
import os
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('--seeds', nargs='+', default=['PUPPER', 'FROG', 'MOSS'])
ap.add_argument('--years', type=int, default=3)
ap.add_argument('--players', nargs='+', default=['routes'], choices=['none', 'storage', 'routes'])
ap.add_argument('--out', default='stats')
args = ap.parse_args()

os.chdir(ROOT)
os.makedirs(args.out, exist_ok=True)
lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.SIM_SEEDS = lua.table_from(args.seeds)
g.SIM_PLAYERS = lua.table_from(args.players)
g.SIM_YEARS = args.years
g.SIM_OUT = args.out.replace(os.sep, '/')
with open(os.path.join(ROOT, 'tools', 'stats_sim.lua'), encoding='utf-8') as f:
    lua.execute(f.read())
for p in g.SIM_WRITTEN.values():
    print(p)
