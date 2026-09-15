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
slot 2 a personal snack picked up from storage. Nothing interrupts a job: when
a morphi is idle and hungry it eats the snack in its pocket, or fetches one from
storage, or eats straight off a bush. After 45 seconds of work a morphi grabs a
snack from storage if it has none and takes a break in the break room. Gold is worth 3, logs 2, food 1 in the final score. Hires cycle forager,
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

## How it plays

You never control a morphi. You mark work and pay for building; idle morphis
do the rest.

- **Mine**: drag a rectangle over stone or snow. A miner digs each marked tile
  once a neighbouring tile is reachable, so tunnels grow inward. Ore under a
  mark yields gold. Drag from a marked tile to clear marks.
- **Storage**: click open ground to place a storage site (2 logs). Any idle
  morphi walks over and builds it. Food can only be stored on built storage
  tiles, one item each, so this is the first thing to build.
- **Bridge**: drag a line over water (1 log per tile). Built tile by tile.
- **Memo**: 1 gold to push nearby work to the front of the queue.
- Logs and gold delivered to the break room go into the stockpile shown in the
  top bar. You start with 4 logs, enough for two storage tiles.

## Controls

- WASD or right-drag to pan, mouse wheel to zoom
- 1 to 5 pick a tool: select, mine, storage, bridge, memo
- Select then click a morphi to see who is complaining
- M mutes, ESC returns to the title

## History

This repo started as Morphi (Feb 2024), a job-queue worker sim that never
shipped, and the game has taken its name back. That code is kept under `legacy/morphi/`. Human Resources reuses its
job queue idea, the noise world from top-down-minecraft, and the tools, UI and
scoring from control-the-environment.
