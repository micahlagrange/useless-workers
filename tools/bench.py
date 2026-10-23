#!/usr/bin/env python3
"""The simulation bench: plays free play headless with the real game code
for many seeds and several years (a year is four seasons) with each of four
players, and reports what their bands do year by year.

    python tools/bench.py --seeds 24 --years 8 --out stats/bench-mylabel

The players (tools/sim_player.lua, Player.act) look at the map at the start
and every 30 game seconds: 'active' opens routes (marks mining and lays
bridges to the nearest bushes, trees and ore out of reach), keeps storage
free (floor spots, a bin when logs are spare) and builds a bed for every
morphi (and since the hatchlings epic weaves nests, digs clay for shinies
and lets the job manager set caretakers and hunters); 'none' does nothing;
'dig' only digs and bridges; 'nests' only weaves nests. In free play the
'migr' column counts new eggs, and deaths count with the starved. Each run is one seed and one player, reproducible from the
seed, in its own process (LuaJIT through lupa when it has it, as in LOVE).
For every player and year it aggregates over the seeds (mean, sd, min, max):
survival, morphis lost (starved, left), band size at year end, migrants,
morale average and the share of morphi time above 80 and below 30, time
working / eating / resting / sulking / idle, goods delivered per season
(food, logs, gold), beds built, trades and fun events per morphi per season
(fun is zero until it exists), complaints and hardships by reason, the
stockpile at year end, fed %, hunger drain and score. It prints a short
report (a table per player, the tipping points, per-seed outliers) and
writes into --out: report.txt, seasons.csv (every season of every run, raw
counts in morphi-seconds) and years.csv (the aggregates), and says how fast
it ran. Runs are spread over all cores but one (--jobs), longest first; the
numbers do not depend on how many processes run them. 24 seeds x 8 years x 4
players takes about 20 s at 90 s seasons and under a minute at 300 s on a
12-thread machine (some 700-800 game seconds per real second per process).
The step is 1/30 s (Bench.DT in tools/bench.lua says why; --dt to change).
--set runs Lua after the constants load, for trying numbers without editing
them, e.g. --set "QUARTER_SECONDS = 90" --set "DAY_SECONDS = QUARTER_SECONDS
/ DAYS_PER_SEASON". --strategies runs only some players. Needs lupa, like
the tests (BENCH_LUA=plain uses lupa's plain Lua instead of LuaJIT).
Bench output goes in stats/, which is never committed.
"""
import argparse
import os
import sys
import time
from multiprocessing import Pool

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRATEGIES = ['active', 'none', 'dig', 'nests']


LUA = os.environ.get('BENCH_LUA', 'luajit')


def runtime():
    # LuaJIT as in LOVE when lupa has it (BENCH_LUA=plain forces lupa's default Lua)
    try:
        if LUA != 'luajit':
            raise ImportError
        from lupa import luajit21 as flavour
    except ImportError:
        import lupa as flavour
    lua = flavour.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = "./?.lua;./?/init.lua;" .. package.path')
    return lua


def run_one(job):
    seed, strategy, years, difficulty, overrides, dt = job
    os.chdir(ROOT)
    lua = runtime()
    bench = lua.execute("return dofile('tools/bench.lua')")
    if dt:
        bench.DT = dt
    bench.loadGame(lua.table_from(overrides))
    started = time.perf_counter()
    run = bench.runOne(seed, strategy, years, difficulty)
    wall = time.perf_counter() - started
    return bench.serialize(run), wall, run.gameSeconds


def seed_names(n):
    return ['BENCH%02d' % (i + 1) for i in range(n)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--seeds', type=int, default=12, help='how many seeds (BENCH01, BENCH02, ...)')
    ap.add_argument('--seed-list', nargs='+', help='these seeds instead')
    ap.add_argument('--years', type=int, default=6)
    ap.add_argument('--strategies', nargs='+', default=STRATEGIES, choices=STRATEGIES)
    ap.add_argument('--difficulty', type=int, default=1)
    ap.add_argument('--set', action='append', default=[], help='Lua run after the constants load')
    ap.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 2) - 1),
                    help='processes (default: all cores but one)')
    ap.add_argument('--dt', type=float, default=None, help='simulation step in seconds (default Bench.DT)')
    ap.add_argument('--out', default='stats/bench')
    ap.add_argument('--label', default=None)
    args = ap.parse_args()

    seeds = args.seed_list or seed_names(args.seeds)
    jobs = [(s, st, args.years, args.difficulty, args.set, args.dt) for st in args.strategies for s in seeds]
    procs = max(1, min(args.jobs, len(jobs)))
    # the longest runs first (bands that live longest), so no core waits at the end;
    # every run is its own Lua state, so the order and the process count change nothing
    first = {'active': 0, 'dig': 1, 'nests': 2, 'beds': 2, 'none': 3}
    order = sorted(range(len(jobs)), key=lambda i: first[jobs[i][1]])
    started = time.perf_counter()
    with Pool(procs) as pool:
        out = pool.map(run_one, [jobs[i] for i in order], chunksize=1)
    elapsed = time.perf_counter() - started
    done = [None] * len(jobs)
    for i, d in zip(order, out):
        done[i] = d
    results = [d[0] for d in done]
    run_wall = sum(d[1] for d in done)
    game_seconds = sum(d[2] for d in done)

    os.chdir(ROOT)
    lua = runtime()
    bench = lua.execute("return dofile('tools/bench.lua')")
    bench.applyOverrides(lua.table_from(args.set))
    if args.dt:
        bench.DT = args.dt
    runs = lua.table_from([bench.deserialize(r) for r in results])
    label = args.label or os.path.basename(os.path.normpath(args.out))
    meta = lua.table_from({'label': label, 'seeds': len(seeds), 'difficulty': args.difficulty})
    report = bench.report(runs, args.years, meta)
    report += '\nSeeds: %s.%s\n' % (' '.join(seeds), (' Overrides: ' + ' ; '.join(args.set)) if args.set else '')
    report += ('Speed: %d runs, %.0f game seconds in %.1f s wall clock on %d processes, step %.4f s; '
               '%.0f game seconds per real second per core (%.2f s per run on average).\n') % (
        len(jobs), game_seconds, elapsed, procs, bench.DT,
        game_seconds / max(run_wall, 1e-9), run_wall / len(jobs))
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, 'report.txt'), 'w', encoding='utf-8') as f:
        f.write(report)
    with open(os.path.join(args.out, 'seasons.csv'), 'w', encoding='utf-8', newline='') as f:
        f.write(bench.seasonsCsv(runs))
    with open(os.path.join(args.out, 'years.csv'), 'w', encoding='utf-8', newline='') as f:
        f.write(bench.yearsCsv(runs, args.years))
    sys.stdout.write(report)
    print('written to', args.out)


if __name__ == '__main__':
    main()
