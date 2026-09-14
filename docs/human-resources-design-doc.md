# Human Resources

**Working title.** Alternate: *Middle Management Simulator*.
**Tagline:** Control the environment. The employees will manage themselves. Badly.

A jam-scale god sim for LÖVE2D. You never control a worker. You dig, blast, and bridge a procedurally generated map so that a handful of hungry AI employees can reach fruit and carry it to the break room. Every ninety seconds a Quarterly Report grades you on productivity, complaints, and attrition. Keep them fed and headcount grows. Let them starve and they quit, one by one, until Human Resources is just you.

Built from parts that already exist across five previous jam repos. Nothing in this doc needs a new library.

---

## 1. Pitch

Genre: indirect-control colony sim, single screen plus camera, one sitting.
Session length: six minutes for a full game (four quarters), endless mode after.
Platforms: web (love.js), Windows, macOS, AppImage, all via the existing makelove GitHub Actions pipeline and butler to itch.
Player fantasy: you are the manager who cannot do the work, only rearrange the building.

## 2. Design pillars

1. **Control the environment, not the characters.** Every player verb changes tiles. No worker ever takes a direct order.
2. **The workers are the comedy.** Complaint bubbles, giving up, wandering off. The sim should be legible enough that the player laughs at a specific employee.
3. **Procedural map, deterministic seed.** Every run is a new office park. A seed box on the title screen lets people share a good one.
4. **Ship in seven days.** Every feature below is tagged Must, Should, or Cut. Must is the game. Should is day five and six. Cut does not happen this jam.

## 3. Core loop

```
        +--------------------------------------------------+
        |  QUARTER (90 s)                                  |
        |                                                  |
   fruit ripens ---> job posted ---> nearest idle worker    |
        ^              on queue         claims it           |
        |                                  |                |
        |                          path to fruit (A*)       |
        |                                  |                |
        |                   blocked? ---> complain, give up |
        |                                  |     ^          |
        |                            player digs / blasts / |
        |                            bridges the tile       |
        |                                  |                |
        |                          carry fruit to           |
        |                          BREAK ROOM (+1 output)   |
        +--------------------------------------------------+
                               |
                      QUARTERLY REPORT
            output, complaints, quits, fed %
            hires arrive, budget refills, next quarter
```

Moment to moment, the player is scanning for a complaint bubble, finding the tile that caused it, and spending budget on the right tool to fix it. The tension is that budget refills once per quarter and workers starve continuously.

## 4. World

**Source:** `top-down-minecraft/src/noise.lua`, `worley.lua`, `tilecolorbynoise.lua`; `control-the-environment/src/world.lua`.

- Fixed-size map for the jam: 96 by 64 tiles at 16 px. Infinite chunk streaming from top-down-minecraft is **Cut**; a bounded grid keeps A* cheap and the report meaningful.
- Altitude from layered simplex noise (10 octaves, scale .02 as already tuned). Altitude bands reuse the existing thresholds:

| Tile | Altitude | Passable | Player can change it |
|---|---|---|---|
| Water | 0.00 to 0.06 | No | Line tool builds a bridge |
| Grass | 0.06 to 0.60 | Yes | Fruit trees grow here |
| Dirt | Grass tiles that have been dug or walked heavily | Yes | Cosmetic |
| Stone | 0.60 to 0.97 | No | Dig (one tile) or Explode (3 by 3) turns it to dirt |
| Snow | 0.97 to 1.00 | No | Explode only |

- Colors come straight from `control-the-environment/src/constants.lua` (GRASS_COLORS, DIRT_COLORS, WALL_COLORS) with a small random brightness jitter per tile, the trick from the Jan 2026 commit.
- **Break room:** one 2 by 2 depot placed on the largest grass region near map center at generation time. Fruit delivered here is the score. Fruit eaten on the spot feeds the worker but scores nothing.
- **Fruit trees:** spawn on grass at a fixed percentage per quarter (FRUIT_PERCENTAGE style), capped at MAX_FRUIT. A tree ripens every 20 seconds and posts a harvest job. Roughly a third of trees should generate on grass pockets that are walled in by stone or water, so the player always has something to fix.

## 5. Workers

**Source:** `control-the-environment/libs/character.lua` (A*, target selection, frustration, complaints); `useless-workers/src/worker.lua`, `src/needs/hunger.lua`, `src/behavior/queue.lua`.

Each worker is a `classic` object with:

- **Hunger** 0 to 100, drains at 1.5 per second on Manager difficulty. Eating a fruit restores 40. At 0 the worker quits: stops working, walks toward the map edge, and is removed. Quits count on the report.
- **Patience** (from CTE `secondsWithoutTarget` and `giveUpOnTarget`): if a path fails or takes longer than 8 seconds, the worker complains, drops the job back on the queue, and idles for 3 seconds. Every complaint counts on the report.
- **Icks** (already in CTE): a tile that caused a give-up is remembered as an ick for 30 seconds so the same worker does not immediately re-pick it.
- **States:** `idle`, `walking`, `harvesting`, `carrying`, `eating`, `complaining`, `quitting`. State drives the anim8 animation and the speech bubble.

**Decision rule** when idle, every 0.5 seconds:

1. If hunger under 30, take the nearest reachable fruit and eat it there. Survival beats output.
2. Otherwise take the oldest job on the queue that has a path (first come, first served, exactly as Morphi does it).
3. Otherwise wander (Morphi's `takeWanderJob`, flip facing every few seconds).

**Job queue** (`useless-workers/src/behavior/queue.lua`): a plain FIFO of `{type, x, y, postedAt}`. Job types for the jam: `harvest` (go to tree, pick, carry to break room) and `clear` (Should: walk to a rubble tile after an explosion and tidy it, purely for the animation). One worker per job.

**Headcount:** start with 4 workers on Manager. Each Quarterly Report hires `floor(output / 5)` new workers, minimum 1 if nobody quit. Cap at 12 to protect pathfinding.

## 6. Player tools

**Source:** `control-the-environment/src/abilities.lua`, `ui.lua`, `buttons.lua`, `scoring.lua`.

| Tool | Effect | Budget cost | Tag |
|---|---|---|---|
| Select | Default cursor. Click a worker to see name, hunger, current job. | 0 | Must |
| Dig | Stone to dirt, one tile | 1 | Must |
| Explode | 3 by 3 stone and snow to dirt, with the existing screen shake from `changing-sides/src/shake.lua` | 4 | Must |
| Line | Drag a straight line across water to lay a bridge, cost per tile | 1 per tile | Must |
| Memo | Pin a tile. Posts a `harvest` job for any tree in a 5 tile radius at the front of the queue. Lets the player steer without controlling. | 2 | Should |
| Drag | Right mouse pans the camera, already in CTE | 0 | Must |

**Budget** replaces CTE's `ability_score`. Each quarter starts with 10 plus last quarter's output. Unspent budget carries over. Upgrades from CTE's `upgradeAvailable` stay: every 25 lifetime output unlocks one upgrade pick from Explode radius 5 by 5, Line cost halved, or one extra hire per quarter.

## 7. Economy and scoring

**Quarterly Report** (a full-screen card that pauses the sim for a moment, like the win and lose screens in ASCiickers):

| Line | Source |
|---|---|
| Output | Fruit delivered to the break room this quarter |
| Fed % | Average hunger across workers, sampled every second |
| Complaints | Count of give-ups |
| Attrition | Workers who quit |
| Grade | S, A, B, C, F from output minus complaints minus 3 times attrition |

Final score after four quarters is the sum of output, minus 3 per quit, times a difficulty multiplier. High score is saved per difficulty with the same partitioned save file scheme as `changing-sides` (`difficultyN.highscore`), with the in-memory fallback for love.js.

**Difficulties** (cycle on the title screen, same as ASCiickers):

| Name | Hunger drain / s | Starting workers | Multiplier |
|---|---|---|---|
| Intern | 1.0 | 5 | 0.5 |
| Manager | 1.5 | 4 | 1.0 |
| Director | 2.0 | 3 | 1.5 |
| Unlimited PTO | 2.5 | 2 | 2.0 |

## 8. Win and lose

- **Win:** the fourth Quarterly Report posts with at least one worker still employed. Show the Annual Review, then offer Endless mode (quarters keep coming, hunger drain rises 0.1 per quarter).
- **Lose:** headcount reaches zero at any time. The lose screen is a single line: "Human Resources has been notified." Restart resets timers, queue, scoring, and re-rolls the seed unless the player locked it.

## 9. UI

**Source:** `control-the-environment/src/ui.lua`, `camera.lua`; `changing-sides/main.lua` for the notification box and menus.

- Camera: WASD or right-drag to pan, wheel to zoom, clamped to the map.
- Bottom bar: one button per tool, the current tool drawn as the cursor (CTE already does this). Budget shown at the right end.
- Top bar: quarter number, countdown, headcount, fed %, complaints this quarter.
- Alerts with icons (already in CTE): a complaint alert lists the worker name and blinks the offending tile until the player clicks it.
- Title screen: logo, difficulty cycler, seed box, high score for the selected difficulty, controls hint.
- Debug overlays stay behind the DEBUG flag: tile grid, paths, job queue dump.

## 10. Art and audio

- 16 px tiles, nearest filter, Pyxel Edit sheets, same as every LÖVE jam so far.
- Workers: reuse the four-direction walk sheet from CTE, add a carry frame with a fruit over the head and a two-frame complain pose with a bubble. Give each worker a random shirt tint so complaints are about "the blue one".
- Fruit: three sprites, no gameplay difference.
- Break room: a 2 by 2 tile with a water cooler and a coffee maker, a nod to Inevitable Brew.
- Audio: reuse `audio.lua` and `soundmanager.lua` from CTE. One looping theme, one tense loop for the last 15 seconds of a quarter, sfx for dig, explode, bridge, complaint, quit, report, hire. Long sounds pause music the way ASCiickers does it.

## 11. Tech plan

LÖVE 11.5, Lua 5.1 compatible for love.js. Libraries, all vendored already: `classic`, `anim8`, `luafinding`, `heap`, `vector`, `tween`.

Reuse map, file by file:

| New module | Copied or adapted from |
|---|---|
| `src/world.lua` | `top-down-minecraft/src/{world,noise,worley,tilecolorbynoise}.lua` for generation; `control-the-environment/src/world.lua` for tile mutation at the mouse |
| `src/worker.lua` | `control-the-environment/libs/character.lua` plus hunger from `useless-workers/src/needs/hunger.lua` |
| `src/behavior/{queue,jobs,task}.lua` | `useless-workers/src/behavior/` unchanged except for the new job types |
| `src/abilities.lua`, `src/buttons.lua`, `src/ui.lua`, `src/camera.lua` | `control-the-environment/src/` |
| `src/scoring.lua` | `control-the-environment/src/scoring.lua`, renamed fields |
| `src/highscore.lua` | the save and load functions in `changing-sides/main.lua` |
| `src/shake.lua`, `src/explosion.lua` | `changing-sides/src/` |
| `src/audio.lua`, `src/soundmanager.lua` | `control-the-environment/src/` |
| `src/system/{pub-sub,timer}.lua` | `useless-workers/src/system/` |
| `conf.lua`, `makelove.toml`, `.github/workflows/build.yml`, `serve.sh` | `control-the-environment`, with the game name actually filled in this time |

Performance guardrails: at most 12 workers, each re-plans at most twice per second, A* runs on the bounded 96 by 64 grid with `luafinding` and the existing `heap`. Path results are cached per worker until the target tile or any tile on the path changes. World mutation publishes a `tile_changed` event on pub-sub so cached paths invalidate cheaply.

Tests: keep the `tst/` folder and `luaunit` from useless-workers. Unit test the queue, hunger math, and the report grade. Nothing else.

## 12. Seven-day schedule

This follows the actual commit rhythm from the last four jams: CI green on day one, "it's kinda fun" on day four, audio on day six.

| Day | Goal | Done when |
|---|---|---|
| 1 | Template repo, CI building all targets, bounded noise world drawn, camera pans and zooms | A love.js build uploads from Actions |
| 2 | Workers spawn, hunger drains, they path to fruit and eat | A worker starves and quits on screen |
| 3 | Job queue, break room, delivery counts, Dig and Explode work | Output number goes up when a worker delivers |
| 4 | Quarter timer, Quarterly Report, hires and quits, Line tool | Play a full four-quarter game. Is it fun? If not, tune hunger and fruit before adding anything |
| 5 | Top and bottom bars, alerts, difficulty cycler, high score save, title and lose screens | Someone else can play it without being told the controls |
| 6 | Sprite pass, worker tints, complaint bubbles, music and sfx, Memo tool if time | Sounds like a game |
| 7 | Balance across four difficulties, pick a default seed, logo, itch page text, ship | Butler push succeeds, play the web build once |

## 13. Scope

**Must:** bounded noise world, workers with hunger and A*, harvest job queue, break room delivery, Dig, Explode, Line, quarter loop with report, four difficulties, high score, title and lose screens, CI to itch.

**Should:** Memo tool, upgrades, complaint alerts that blink the tile, clear job, worker names and tints, tense music in the last 15 seconds, Endless mode.

**Cut:** infinite chunk streaming, morale as a second need, multiple worker types, save game, multiplayer, any menu that is not the title screen.

## 14. Risks

- **The sim never becomes a game.** Morphi had workers and a queue and stopped at "ui things are happening". The day-four checkpoint exists for this. If the four-quarter game is not fun by end of day four, cut Line and Memo and spend day five on hunger and fruit tuning only.
- **Pathfinding cost.** Twelve workers re-planning every frame on a 6,144 tile grid will stutter in love.js. The guardrails in section 11 are not optional.
- **Unreachable fruit feels like a bug instead of a puzzle.** The complaint bubble must name the worker and the alert must point at the tile. Without that feedback the player thinks the AI is broken.
- **Scope creep in the world gen.** The noise code is fun to tweak. Lock the altitude bands on day one and do not reopen them.
- **Windows path case bugs.** Already bit ASCiickers. Lowercase every asset filename from the start.

## 15. Open questions

1. Title: *Human Resources* or *Middle Management Simulator*? Decide before the logo on day seven, not before.
2. Fruit or coffee? Coffee as the resource makes the break room joke land harder and reuses the Inevitable Brew premise. Fruit already has sprites and a spawn model in CTE. Default to fruit, swap art on day six if it is cheap.
3. Does the Memo tool make the game too easy by turning it into direct control? Playtest on day six with it enabled and disabled.
