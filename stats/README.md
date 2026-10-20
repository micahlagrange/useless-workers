# Run stats

Exported runs go here, for reading with `tools/stats_report.py`.

- **From the game:** MENU, then the `...` in its corner (tester tools), or the
  game over / end of year screen: EXPORT asks for a short note on what was fun
  and what was not, then writes the run. On the desktop it lands in the save
  folder's `stats/` (Windows: `%APPDATA%/LOVE/morphis/stats/`); in a browser
  it downloads; on an Artifact test page it goes to the page's database and
  Claude pulls it in here with `tools/stats_inbox.py` (see CLAUDE.md).
- **Without playing:** `python tools/stats_sim.py` plays free play headless with
  a simple player and writes `stats/sim-<seed>-<player>.json` (not committed).

A run file holds one row per day (9 days a season: band size, hunger, morale,
time working / eating / resting / idle / sulking, stock, everything gathered,
arrivals and departures), the map at the start of every day (the first day
whole, then only what changed), every event, the milestones and a plain history.

    python tools/stats_report.py stats/RUN.json            # season table, milestones, history
    python tools/stats_report.py stats/RUN.json --graphs   # PNG graphs
    python tools/stats_report.py stats/RUN.json --map 20 --camp
    python tools/stats_report.py stats/RUN.json --step 18 20 --camp
    python tools/stats_report.py stats/*.json              # one line per run
