# Run stats

Working files only: sims, graphs, runs being looked at. Nothing here is
committed (`.gitignore` keeps everything but this file). Runs Micah plays are
kept in the archive outside the repo, `C:/Users/sixst/Documents/morphis-stats-archive`,
each named `<exported>-<first words of the note>-b<build>.json` so the names
sort in the order the runs were made.

How a played run gets to the archive:

1. **In the game:** the DEV button on the top bar (tester tools), or the
   screen at the end of any game (game over, end of year, level clear or
   failed): EXPORT asks for a short note on what was fun and what was not,
   then shows the run as JSON text with COPY and DOWNLOAD. In a browser the
   text sits in a box over the game, so it can be highlighted and copied by
   hand too.
2. **In the run viewer** (https://claude.ai/artifact/MkPjsiF2xNFFwgc3SRYMMf):
   paste the text and press VIEW AND SAVE. It shows the run and keeps it in
   the viewer's database under its name.
3. **On this machine:** Claude pulls the viewer's saved runs (ArtifactData
   `list`, collection `runs`, `out_dir` `stats/inbox`) and runs
   `python tools/stats_archive.py --clean`, which writes new ones to the archive.

Without playing: `python tools/stats_sim.py` plays free play headless with a
simple player and writes `stats/sim-<seed>-<player>.json`.

A run file holds one row per day (9 days a season: band size, hunger, morale,
time working / eating / resting / idle / sulking, stock, everything gathered,
arrivals and departures, where each morphi stands), the map at the start of
every day (the first day whole, then only what changed), every event, the
milestones and a plain history.

    python tools/stats_report.py RUN.json            # season table, milestones, history
    python tools/stats_report.py RUN.json --graphs   # PNG graphs
    python tools/stats_report.py RUN.json --map 20 --camp
    python tools/stats_report.py RUN.json --step 18 20 --camp
    python tools/stats_report.py A.json B.json       # one line per run
