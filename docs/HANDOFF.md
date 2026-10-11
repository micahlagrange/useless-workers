# Morphis: handoff for the next session

Read this first. It covers how the game is built, tested and shipped, where
everything lives, what is done, and what was asked for next.

## Repo, branch, deploy

- Repo: `micahlagrange/useless-workers`. All work is on branch
  `claude/game-jam-repo-analysis-ao9tmq`. Never push to another branch.
- Every push runs `.github/workflows/build.yml`: unit tests (`pip install lupa
  && python3 tst/run.py`), makelove builds (lovejs, win64, macos, appimage),
  `tools/patch_lovejs.py` makes the web page fill the viewport, then butler
  pushes four channels to itch. The web build is live within about two
  minutes at https://multivoxmuse.itch.io/morphi.
- Commit trailers used so far:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01NHhqKHNRvgVpjJCoSRjVua`.
  Author identity: `-c user.name="Micah Turner" -c user.email="turner.micah@gmail.com"`.
- makelove packs only files git knows about: commit (or at least `git add`)
  new files before building locally, or the build will miss them.
- After each push the habit has been to schedule a check of the Actions run
  and report the itch link.

## Local workflow

- Tests: `python3 tst/run.py` (luaunit under lupa, Lua 5.5 parser; keep code
  5.1 compatible). About 80 tests across `tst/*_test.lua`. The level tests
  play every level with the real morphi AI.
- Syntax check all Lua quickly with lupa `compile` (no `luac` here).
- Web build locally: `makelove lovejs`, then
  `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`,
  unzip into `makelove-build/html`, serve with `python3 -m http.server 8000`
  from there, open `http://localhost:8000/morphis/`. `serve.sh` does this.
- Browser checks use Playwright from `/opt/node22/lib/node_modules/playwright`
  with chromium at `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`
  (`--no-sandbox --use-gl=swiftshader`). Use sparingly: the owner asked to
  keep Playwright runs short. Phone emulation: viewport 852x393, hasTouch,
  isMobile, deviceScaleFactor 3.
- Font is `assets/fonts/commodore64.ttf` (wide; always use `printFit`).

## Architecture (LÖVE 11.4, love.js for web)

Pure logic (no love calls, unit tested): `src/constants.lua` (every tunable),
`util`, `rng`, `noise`, `world` (tiles, nodes, items, sites, storage, beds,
rivers, reachability, spend/refund), `jobs` (queue, `takeNearest` with atomic
claim), `pathfinder`, `worker` (the morphi AI), `scoring`, `abilities`
(tools: mine areas, floor, bin, bed, bridge lines, cancel/swap), `highscore`
(keyed saves), `levels` + `campaign` (survival levels).
LÖVE side: `camera`, `audio`, `effects`, `view` (world drawing), `ui` (HUD,
title, panels, scaled layout, touch), `main.lua` (states and input).

Key rules in the current build:
- Diets: every morphi eats one food (Pupper steak, Woofoof fish, Twins
  cheese, Cwab chili, Blob candy). Foragers pick any food into storage.
- Storage: floor spot (free, 1 item) and bin (1 log, 4 items, top-down art).
  Beds (2 logs) are woodwork built only by the lumberjack. Bridges 1 log per
  tile. Mining is free and only miners do it. Build marks can be cancelled or
  swapped with the tools. Build marks draw as ghosts.
- Jobs: nearest job the morphi can path to, claimed atomically. Unreachable
  jobs stay queued. Morale system: hardships and hunger wear morphis down,
  at zero they leave. Hunger complaints are one per cooldown per morphi.
- Modes: campaign of 5 hand built survival levels (`src/levels.lua`), and
  free play (random map, rivers, seasons, migrants). Title picks a level or
  free play. Points spent vs par, three stars at par, progress persists.
- UI: HUD laid out in a virtual space scaled to the window (`UI:layout`),
  touch screens get a bigger font set and near 1:1 scale, quick buttons GOAL
  UNITS FOLLOW - + MUTE MENU, G opens the goal panel (levels open on it),
  U units list, pinch zoom, drag pan with SELECT, zoom capped to keep 20
  tiles on screen. Levels open zoomed to fit the whole map.

## itch settings the owner controls

For phones, the game's embed on itch should be "Click to launch in
fullscreen" with "Mobile friendly" ticked and landscape orientation. The
game fits any frame it is given but cannot change the itch frame.

## Next up (asked for, not done)

1. Arcade mode, to become the default. Survival stays selectable but
   retired. Spec from the owner:
   - every morphi has exactly one job; building is a job, only builder
     morphis build (Twins as builder);
   - no hunger in this mode; the level is won when every morphi has eaten
     once;
   - level 1: no obstacle, the morphi just goes and eats;
   - level 2: a river; bridge it, then both eat;
   - level 3: they are picky and only eat food gathered into bins;
   - level 4: they need living conditions: enough floor tiles for all of
     them (not picky about where);
   - level 5: four walls enclosing the floors, and bins to eat;
   - level 6: the bins must be inside the walls.
   Design notes already decided: new tile types wall (blocks) and door
   (walkable, counts as a wall for the enclosure check); tools in arcade
   SELECT MINE FLOOR BIN WALL DOOR BRIDGE; floors in arcade are living
   space (storage capacity 0); enclosure = flood fill from a floor over
   walkable tiles with doors closed never reaches the map edge; a GOAL
   checklist with live ticks; "ATE n/m" in the top bar; morphis in arcade
   skip hunger, morale and breaks, eat any food, and an arcade test should
   play each level's obvious and par solutions until everyone has eaten.
   `docs/arcade-wip.patch` holds the partial edits made so far (constants,
   jobs, abilities, part of world); apply with `git apply docs/arcade-wip.patch`
   or start clean. It is not committed as code because it was half done and
   broke tests.
2. Walking animations: Cwab and Pupper look great; Woofoof, Twins and Blob
   do not. Compare the sheets in `assets/images/morphis/*-worker-walk.png`
   (16x16 frames in a row, read by `View.new` with anim8) and redraw frames
   where needed.
3. One more morphi: owner said "surprise me". Needs a sheet, a name in
   `MORPHI_SHEET_NAMES`, a diet in `MORPHI_DIET`, a role in `MORPHI_ROLE`
   and `ARCADE_ROLE`, and a food sprite in `FOOD_SPRITE`.
4. The bridge tool's mouse cursor still uses the old line cursor image
   (`assets/images/ui/line_cursor.png`); draw a bridge cursor to match the
   new bridge icon (`UI:iconBridge`).

## Known rough edges

- Portrait phones work but are small; the game hints to turn sideways.
- Gold has no sink since the memo tool was removed; it only scores.
- The old design doc under `docs/human-resources-design-doc.md` describes
  the original corporate theme and is out of date.
