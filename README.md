# Morphis

Control the environment. The employees will manage themselves. Badly.

A LÖVE2D jam game. You never control a morphi. You dig, blast and bridge a
procedurally generated map so hungry morphis can reach their work and carry it
to the break room. Every ninety seconds a Quarterly Report grades you on output,
complaints and attrition. Keep them fed for four quarters.

## The morphis

| Morphi | Role | Works on | Delivers |
|---|---|---|---|
| Pupper, Woofoof | Forager | Bushes on the ground, ripen every 20 s | Food, stocks the break room pantry |
| Twins | Lumberjack | Trees, cut to a stump that regrows | Logs |
| Cwab, the blob | Miner | Gold ore inside stone, worked from the tile next to it | Gold, the mined tile turns to dirt |

Delivered food is a real item on the ground: the closest free tile to the break
room, one per tile. Morphis walk over stored items but try not to idle on them.
Every morphi has two inventory slots: slot 1 holds the work item it is carrying,
slot 2 a personal snack picked up from storage. A hungry morphi with a snack
stops whatever it is doing, eats, and carries on. After 45 seconds of work a
morphi grabs a snack from storage if it has none and takes a break in the break
room. Gold is worth 3, logs 2, food 1 in the final score. Hires cycle forager,
lumberjack, miner.

Design doc (written under the working title Human Resources): [docs/human-resources-design-doc.md](docs/human-resources-design-doc.md)

## Run

```
love .
```

Web build served locally (needs makelove):

```
./serve.sh
```

## Tests

```
./test.sh
```

Uses luajit when installed, otherwise `pip install lupa` and the Python runner in `tst/run.py`.

## Controls

- WASD or right-drag to pan, mouse wheel to zoom
- 1 to 5 pick a tool: select, dig, explode, bridge (drag across water), memo
- Select then click a worker to see who is complaining
- M mutes, ESC returns to the title

## History

This repo started as Morphi (Feb 2024), a job-queue worker sim that never
shipped, and the game has taken its name back. That code is kept under `legacy/morphi/`. Human Resources reuses its
job queue idea, the noise world from top-down-minecraft, and the tools, UI and
scoring from control-the-environment.
