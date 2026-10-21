# Morphis

A bunch of little blobs in a big meadow. They will look after themselves. Sort of.

A LÖVE2D game. You never steer a morphi. You mark clay to dig, lay bridges
over the streams and set out stashes, baskets and nests around the home nest,
and the morphis do the rest: pick berries, gather sticks, dig up shinies and
carry it all home.

Every morphi has three jobs: a main job it does first, a neutral job for when
the main one has nothing, and a job it dislikes and does only when nothing else
is left. You pick the first two (JOBS on a picked morphi); the disliked one is
part of who it is. The jobs are forager, gatherer, digger, builder, caretaker and hunter.

## The morphis

| Morphi | Loves |
|---|---|
| Pupper | meat |
| Woofoof | fish |
| Twins | cheese |
| Cwab | chili |
| Blob | candy |
| Ribbit | grapes |

| Job | Works on | Brings home |
|---|---|---|
| Forager | berry bushes, ripe every 20 s | food, put down on a stash or in a basket |
| Gatherer | trees | sticks; the tree regrows |
| Digger | marked clay, and the shinies hidden in it | shinies |
| Builder | anything marked to build | stashes, baskets, nests, bridges |
| Hunter | critters hopping about the meadow | meat, the only way to get it |
| Caretaker | babies that need something | play, a wash (with a tuft of grass), a meal, a nap |

Food is a real thing on the ground: the closest free stash to the home nest,
one per stash. Every morphi has two pockets: one for what it is carrying, one
for a snack. Nothing interrupts a job: when a morphi is idle and hungry it eats
the snack in its pocket, fetches one from a stash, or eats straight off a bush.
Shinies are worth 3, sticks 2, food 1 in the final score.

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

You never steer a morphi. You mark work and pay for building; idle morphis
do the rest.

- **Dig**: drag a rectangle over clay or hard dirt. A digger digs each marked
  tile once a tile next to it can be reached, so tunnels grow inward. Shinies
  are hidden in the clay, a few in every patch, and only turn up when dug: go
  looking. Drag from a marked tile to clear marks.
- **Stash**: tap open ground for a free leaf-mat stash. It holds one thing.
  Food can only be put down on a stash or in a basket, so this comes first.
- **Basket**: 1 grass, holds four things.
- **Nest**: 2 sticks, 2 grass and 1 leaf. A nap in a nest is shorter and does
  more good.
- **Bridge**: drag a line over water (1 stick a tile). Two streams cut every
  meadow and plenty of good things sit on the far banks.
- **Mood**: grumbles and hunger wear a morphi down; food and naps cheer it up.
  At zero it packs a tiny bag and leaves. Press U to see everyone at once.
- Sticks and shinies brought home go into the pile shown in the top bar. You
  start with 4 sticks.

## Controls

- WASD or right-drag to pan, mouse wheel to zoom
- The window can be any size; the HUD scales to fit. F11 toggles fullscreen.
- On a phone or tablet: drag to pan with the SELECT tool, pinch to zoom, and
  use the buttons along the top.
- Title: LEFT / RIGHT pick free play or an old level
- 1 to 6 pick a tool: select, dig, stash, basket, nest, bridge
- Pick a morphi to see what it is up to: FOLLOW, JOBS (or J), and [ ] for the
  previous and next morphi
- U opens the list of everyone, with FOLLOW and JOBS on each row
- M mutes, ESC asks before returning to the title

## History

This repo started as Morphi (Feb 2024), a job-queue worker sim that never
shipped, and the game has taken its name back. That code is kept under `legacy/morphi/`. Human Resources reuses its
job queue idea, the noise world from top-down-minecraft, and the tools, UI and
scoring from control-the-environment.
