#!/usr/bin/env python3
"""Reads a run's stats JSON (in-game EXPORT, or tools/stats_sim.py) and
answers questions about it.

    python tools/stats_report.py RUN.json                 # summary, season table, history
    python tools/stats_report.py RUN.json --graphs        # PNG graphs next to the file
    python tools/stats_report.py RUN.json --map 12        # the map at the start of day 12
    python tools/stats_report.py RUN.json --step 10 14    # days 10 to 14, what changed each day
    python tools/stats_report.py RUN.json --diff 12       # only the tiles that changed on day 12
    python tools/stats_report.py A.json B.json ...        # one summary line per run

--crop X0 Y0 X1 Y1 limits a map to part of the world (1-based, inclusive).
--camp crops to the twenty tiles around camp. Graphs need matplotlib.
"""
import argparse
import json
import os
import sys

SERIES = {
    'band': [('pop', 'morphis'), ('hungry', 'hungry'), ('starving', 'starving'), ('lowMorale', 'low morale')],
    'mood': [('hunger', 'average hunger'), ('morale', 'average morale')],
    'time': [('work', 'working'), ('foodTime', 'eating / fetching'), ('rest', 'resting'), ('idle', 'idle'), ('sulk', 'sulking')],
    'gathered': [('food', 'food'), ('logs', 'logs'), ('gold', 'gold')],
    'stock': [('stockLogs', 'logs in stock'), ('stockGold', 'gold in stock'), ('storedFood', 'food in storage')],
    'comings and goings': [('arrived', 'arrived'), ('starved', 'starved'), ('left', 'left (morale)'), ('hardships', 'hardships'), ('trades', 'deals')],
    'the wilds': [('ripeBushes', 'ripe bushes'), ('trees', 'trees'), ('ore', 'gold ore')],
}


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def map_on(run, day):
    maps = run['maps']
    if not maps:
        return []
    grid = [list(r) for r in maps[0]['full']]
    for d in range(1, min(day, len(maps))):
        for x, y, c in maps[d].get('changes') or []:
            grid[y - 1][x - 1] = c
    return [''.join(r) for r in grid]


def camp_of(rows):
    for y, r in enumerate(rows):
        x = r.find('C')
        if x >= 0:
            return x + 1, y + 1
    return 1, 1


def crop(rows, box):
    if not box:
        return rows, 1, 1
    x0, y0, x1, y1 = box
    return [r[x0 - 1:x1] for r in rows[y0 - 1:y1]], x0, y0


def print_map(rows, x0=1, y0=1, marks=None):
    w = len(rows[0]) if rows else 0
    tens = ''.join(str(((x0 + i) // 10) % 10) if (x0 + i) % 10 == 0 else ' ' for i in range(w))
    ones = ''.join(str((x0 + i) % 10) for i in range(w))
    print('     ' + tens)
    print('     ' + ones)
    for i, r in enumerate(rows):
        line = r
        if marks:
            line = ''.join('@' if (x0 + j, y0 + i) in marks else ch for j, ch in enumerate(r))
        print('%4d %s' % (y0 + i, line))


def legend(run):
    return '  '.join('%s %s' % (k, v) for k, v in sorted(run.get('legend', {}).items()))


def season_table(run):
    days = run['days']
    per = run['meta'].get('daysPerSeason', 9)
    print('%-10s %4s %6s %6s %5s %5s %5s %5s %5s %5s %5s' % ('season', 'pop', 'hunger', 'morale', 'idle%', 'food', 'logs', 'gold', 'in', 'out', 'hard'))
    prev = None
    for start in range(0, len(days), per):
        chunk = days[start:start + per]
        last = chunk[-1]
        n = sum(d['pop'] for d in chunk) or 1
        idle = 100 * sum(d['idle'] for d in chunk) / n

        def gain(key):
            return last[key] - (prev[key] if prev else 0)
        print('%-10s %4d %6.1f %6.1f %5.0f %5d %5d %5d %5d %5d %5d' % (
            chunk[0]['season'], last['pop'],
            sum(d['hunger'] for d in chunk) / len(chunk), sum(d['morale'] for d in chunk) / len(chunk), idle,
            gain('food'), gain('logs'), gain('gold'), gain('arrived'), gain('starved') + gain('left'), gain('hardships')))
        prev = last
    print('(each row: band at the end of the season, averages over its days, and what changed in it)')


def summary(path, run, short=False):
    m = run['meta']
    days = run['days']
    last = days[-1] if days else {}
    years = len(days) / (4 * m.get('daysPerSeason', 9))
    head = '%s  seed %s  %s  build %s  %d days (%.1f years)  ended: %s' % (
        os.path.basename(path), m.get('seed'), m.get('difficulty') or m.get('level') or m.get('mode'), m.get('build'), len(days), years, m.get('endedAs', '?'))
    if short:
        print('%s | pop %s  food %s logs %s gold %s  in %s starved %s left %s  milestones %d' % (
            head, last.get('pop'), last.get('food'), last.get('logs'), last.get('gold'), last.get('arrived'), last.get('starved'), last.get('left'), len(run['milestones'])))
        return
    print(head)
    if m.get('blurb'):
        print('player says: "%s"' % m['blurb'])
    print()
    season_table(run)
    print()
    print('milestones (%d, about %.1f a year):' % (len(run['milestones']), len(run['milestones']) / max(years, 0.01)))
    for ms in run['milestones']:
        print('  day %d (%s): %s' % (ms['day'], ms['season'], ms['text']))
    print()
    print('history:')
    for line in run.get('history', []):
        print('  ' + line)


def graphs(path, run):
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        sys.exit('graphs need matplotlib: pip install matplotlib')
    days = run['days']
    xs = [d['day'] for d in days]
    per = run['meta'].get('daysPerSeason', 9)
    out = os.path.splitext(path)[0] + '-graphs'
    os.makedirs(out, exist_ok=True)
    fig, axes = plt.subplots(len(SERIES), 1, figsize=(10, 2.6 * len(SERIES)), sharex=True)
    for ax, (title, keys) in zip(axes, SERIES.items()):
        for key, label in keys:
            ax.plot(xs, [d.get(key, 0) for d in days], label=label, linewidth=1.4)
        for s in range(per + 1, len(days) + 1, per):
            ax.axvline(s - 0.5, color='#999', linewidth=0.5, alpha=0.5)
        ax.set_title(title, loc='left', fontsize=10)
        ax.legend(fontsize=7, loc='upper left', ncol=len(keys))
        ax.grid(alpha=0.2)
    for ms in run['milestones']:
        for ax in axes:
            ax.axvline(ms['day'], color='#c80', linewidth=1.2, linestyle='--')
    axes[-1].set_xlabel('day (grey lines: new season, dashed gold: milestone)')
    fig.suptitle('%s  seed %s' % (os.path.basename(path), run['meta'].get('seed')))
    fig.tight_layout()
    png = os.path.join(out, 'overview.png')
    fig.savefig(png, dpi=110)
    print(png)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('runs', nargs='+')
    ap.add_argument('--graphs', action='store_true')
    ap.add_argument('--map', type=int)
    ap.add_argument('--step', type=int, nargs=2)
    ap.add_argument('--diff', type=int)
    ap.add_argument('--crop', type=int, nargs=4)
    ap.add_argument('--camp', action='store_true')
    args = ap.parse_args()
    if len(args.runs) > 1:
        for p in args.runs:
            summary(p, load(p), short=True)
        return
    path = args.runs[0]
    run = load(path)
    box = args.crop
    if args.camp:
        cx, cy = camp_of(map_on(run, 1))
        box = [max(1, cx - 20), max(1, cy - 12), cx + 20, cy + 12]
    if args.map is not None:
        rows, x0, y0 = crop(map_on(run, args.map), box)
        d = run['days'][args.map - 1]
        print('day %d (%s): %d morphis, hunger %s, morale %s' % (args.map, d['season'], d['pop'], d['hunger'], d['morale']))
        print_map(rows, x0, y0)
        print(legend(run))
    elif args.step:
        for day in range(args.step[0], args.step[1] + 1):
            changes = run['maps'][day - 1].get('changes') or [] if day > 1 else []
            marks = {(x, y) for x, y, _ in changes}
            rows, x0, y0 = crop(map_on(run, day), box)
            d = run['days'][day - 1]
            print('\nday %d (%s): %d morphis, hunger %s, %d tiles changed (@)' % (day, d['season'], d['pop'], d['hunger'], len(changes)))
            print_map(rows, x0, y0, marks)
        print(legend(run))
    elif args.diff is not None:
        changes = run['maps'][args.diff - 1].get('changes') or []
        before = map_on(run, args.diff - 1)
        print('day %d: %d tiles changed' % (args.diff, len(changes)))
        for x, y, c in changes:
            print('  %d,%d  %s -> %s' % (x, y, before[y - 1][x - 1], c))
    elif args.graphs:
        graphs(path, run)
    else:
        summary(path, run)


if __name__ == '__main__':
    main()
