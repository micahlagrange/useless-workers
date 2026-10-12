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
- makelove packs the committed tree (`git ls-tree HEAD`): commit new files
  before building locally. Staging alone is not enough; the web build will
  fail to require a file that is only in the index.
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
- Font is LOVE's built in Vera Sans (`love.graphics.newFont(size)`); the
  old C64 face is gone. `printFit` still picks the largest font that fits.

## Local workflow on Windows (set up 2026-10-11)

- This checkout is a git worktree of `../useless-workers`. It was made from
  WSL; `git worktree repair` from the main checkout fixed the paths for
  Windows git. Redo that if WSL is used again.
- Python 3.10 (pyenv) has `lupa` and `makelove`. Tests: `python tst/run.py`.
- LÖVE 11.5 is at `C:/Program Files/LOVE`. Run the game with
  `"C:/Program Files/LOVE/lovec.exe" .` from the repo root (console build,
  prints Lua errors to the terminal).
- Web build: `python -m makelove lovejs`, then
  `python tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`,
  unzip into `makelove-build/html`, serve that folder with
  `python -m http.server 8000`, open `http://localhost:8000/morphis/`.
- Browser check: node 22 with Playwright 1.64 (chromium installed under
  `%LOCALAPPDATA%/ms-playwright`). `node tools/web_shot.js out.png` loads the
  served page, waits 8 s, and screenshots it; it needs `playwright` resolvable
  from where it runs (`npm i playwright@1.64.0` in a scratch folder works).
- `gh` is logged in as micahlagrange, so push and Actions checks work.

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
- Modes: arcade, the default, six hand built levels (`src/arcade_levels.lua`);
  survival, retired but on the title, five levels (`src/levels.lua`); and
  free play (random map, rivers, seasons, migrants). Points spent vs par,
  three stars at par, progress persists per set (`arcadeN_*`, `levelN_*`).
- Arcade rules (`world.arcade`): no hunger, morale or breaks. Every morphi
  has one job (`ARCADE_ROLE`: Twins builds, Pupper and Woofoof forage,
  Cwab and Blob mine) and eats anything, once, but only after the level's
  `needs` are met (`ARCADE_NEED_ORDER`: bins, floors, enclosed, binsInside;
  `World:arcadeReady`). The level is clear when everyone has eaten. Tools:
  SELECT MINE FLOOR BIN WALL DOOR BRIDGE (`TOOLS_ARCADE`; main swaps
  `ABILITY_ORDER` per mode and relays the HUD). Floors are living space
  (`World:markFloor`, capacity 0); walls block, doors pass. Enclosure
  (`World:enclosure`): fill from each floor over walkable tiles with doors
  shut, must never touch the map edge, and every floor must be reachable
  from camp, so a room needs a door. Stone and water count as walls. A
  builder stands on the camp side of a wall site (`World:reachableAvoiding`)
  so it never walls itself in. `Campaign.goals` is the live checklist, shown
  in the goal panel and in the bottom right of the HUD. `tst/arcade_test.lua`
  plays every level's obvious and par solutions with the real AI.
- UI: HUD laid out in a virtual space scaled to the window (`UI:layout`),
  touch screens get a bigger font set and near 1:1 scale, quick buttons GOAL
  UNITS FOLLOW - + MUTE MENU, G opens the goal panel (levels open on it),
  U units list, pinch zoom, drag pan with SELECT, zoom capped to keep 20
  tiles on screen. Levels open zoomed to fit the whole map.

## itch settings the owner controls

For phones, the game's embed on itch should be "Click to launch in
fullscreen" with "Mobile friendly" ticked and landscape orientation. The
game fits any frame it is given but cannot change the itch frame.

## Done on 2026-10-11

Arcade mode, as specified: six levels, default on the title, survival
retired but selectable. Level 2 pairs Pupper with Twins because only the
builder can bridge. Arcade has no fail state and no clock: the top bar
shows elapsed time, and MENU starts a level over if the points run out.

Then, same day: a readable font and a plain GUI (buttons, checkboxes,
stars), arcade budgets per difficulty (`ARCADE_DIFFICULTIES`, picked on the
title with UP/DOWN) with par set a little above the cheapest build, walk
cycles for Woofoof, Twins and Blob (generated from the old sheets: bob,
lean, squash and stretch), Ribbit the frog as the sixth morphi (a second
builder, joins in arcade 6; lumberjack in the wilds, eats grapes), and a
bridge cursor (`assets/images/ui/bridge_cursor.png`).

## Next up (asked for, not done)

1. Walking animations (DONE, see above; redraw by hand if the generated
   cycles are not enough): Cwab and Pupper look great; Woofoof, Twins and Blob
   do not. Compare the sheets in `assets/images/morphis/*-worker-walk.png`
   (16x16 frames in a row, read by `View.new` with anim8) and redraw frames
   where needed.
2. One more morphi (DONE: Ribbit). To add another: a sheet, a name in
   `MORPHI_SHEET_NAMES`, a diet in `MORPHI_DIET`, a role in `MORPHI_ROLE`
   and `ARCADE_ROLE`, a food sprite in `FOOD_SPRITE`, a grid letter in
   `FOOD_CHAR`, and a level that lists it.
3. The bridge cursor (DONE).

## Known rough edges

- Portrait phones work but are small; the game hints to turn sideways.
- Gold has no sink since the memo tool was removed; it only scores.
- The old design doc under `docs/human-resources-design-doc.md` describes
  the original corporate theme and is out of date.
