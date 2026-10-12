# Morphis: handoff for the next session

Read this first. The top is the state as of the handoff and what is still
open. Below that: how the game is built, tested and shipped, and where
everything lives.

## State at handoff (2026-10-12)

- Branch `claude/game-jam-repo-analysis-ao9tmq`, head `fede209`. Working
  tree clean, everything pushed, CI green, web build live at
  https://multivoxmuse.itch.io/morphi.
- Tests: all passing across `tst/*_test.lua` (`python tst/run.py`).
- Sessions run on this Windows machine in the worktree
  `C:\Users\sixst\Documents\github\useless-workers-hr`, from the Claude
  desktop app (Code tab). Remote Control is already on for these sessions,
  so the owner can follow along from another device; there is nothing to
  set up.

### Done in the last session (2026-10-11 and 12)

1. Arcade mode, now the default: six levels in `src/arcade_levels.lua`,
   walls, doors, floors as living space, the enclosure check, a live goal
   checklist, one job per morphi, no hunger, clear when everyone has eaten.
   Survival stays on the title as a retired set.
2. A readable font (LOVE's Vera Sans, linear filtered) and a plain GUI:
   buttons on every panel, drawn checkboxes and stars, no bracket or
   key-hint conventions.
3. Arcade budgets per difficulty (`ARCADE_DIFFICULTIES`, Easy default), more
   bushes, and par set above the cheapest build so it can be beaten.
4. Walk cycles for Woofoof, Twins and Blob; Ribbit the frog as the sixth
   morphi; a bridge cursor; morphis step off a tile that turns into a wall.
5. Restart (`fede209`): the MENU panel offers RESTART in every mode, and a
   stuck arcade level (no logs, nothing being built, no hungry morphi can
   reach food, for five seconds) shows a RESTART LEVEL button; R does the
   same.

### Open items and things to check

None of these block anything. They are what the previous session did not
finish verifying or left as a judgement call.

- **Bridge cursor in game.** `assets/images/ui/bridge_cursor.png` loads
  without error and the UI maps the BRIDGE tool to it, but no screenshot
  caught it under the mouse. Select BRIDGE in a level and look.
- **Generated walk cycles.** Woofoof, Twins and Blob were not redrawn by
  hand. Their frames come from the old sheets with a bob, a lean, and
  squash and stretch (Blob also had its blurry pixels snapped to a short
  palette). Cwab and Pupper are untouched. If the owner wants more life,
  redraw the 16x16 frames in `assets/images/morphis/*-worker-walk.png`.
  `View.new` reads any number of frames from the sheet width.
- **Level 2 roster.** The spec said "a river; bridge it, then both eat".
  Only the builder can bridge, so level 2 is Pupper plus Twins rather than
  Pupper plus Woofoof. Easy to change in `src/arcade_levels.lua` if the
  owner would rather introduce Twins later; the obvious and clever
  solutions do not depend on who the second morphi is.
- **Arcade level 6 now has six morphis** (Ribbit joins) and a bigger
  obvious house. Its clever solution still fits the stone room.
- **Level 1 has a few points to spend** on Easy and Normal though there is
  nothing to build. Harmless; lets a new player try the tools.
- **Font weight.** Vera Sans at 15 px looks thin under software rendering
  (the headless checks). On a real GPU it is fine. If the owner wants it
  bolder, raise the `hud` size in `UI.new` or draw labels twice offset by
  a pixel.
- **Commit trailers.** The last session used only the Co-Authored-By
  trailer; it had no session URL for a Claude-Session trailer.
- **Linux paths** in the "Local workflow" section below are from the first
  session's cloud container. On this Windows machine use the Windows
  section instead.

### How to resume

1. `cd C:\Users\sixst\Documents\github\useless-workers-hr`, `git pull`.
2. `python tst/run.py` to confirm green.
3. Run the game: `"C:/Program Files/LOVE/lovec.exe" .`
4. For a web check: commit first (makelove packs the committed tree), then
   follow the Windows section below.
5. Commit with the author identity and trailer listed under "Repo, branch,
   deploy", push, and watch the Actions run with `gh run watch`.

## Repo, branch, deploy

- Repo: `micahlagrange/useless-workers`. All work is on branch
  `claude/game-jam-repo-analysis-ao9tmq`. Never push to another branch.
- Every push runs `.github/workflows/build.yml`: unit tests (`pip install lupa
  && python3 tst/run.py`), makelove builds (lovejs, win64, macos, appimage),
  `tools/patch_lovejs.py` makes the web page fill the viewport, then butler
  pushes four channels to itch. The web build is live within about two
  minutes at https://multivoxmuse.itch.io/morphi.
- Commit trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
  The first session also added
  `Claude-Session: https://claude.ai/code/session_01NHhqKHNRvgVpjJCoSRjVua`;
  add a Claude-Session trailer when the session has a URL.
  Author identity: `-c user.name="Micah Turner" -c user.email="turner.micah@gmail.com"`.
- makelove packs the committed tree (`git ls-tree HEAD`): commit new files
  before building locally. Staging alone is not enough; the web build will
  fail to require a file that is only in the index.
- After each push the habit has been to watch the Actions run and report
  the itch link.

## Local workflow on Windows (this machine)

- This checkout is a git worktree of `../useless-workers`. It was made from
  WSL; `git worktree repair` from the main checkout fixed the paths for
  Windows git. Redo that if WSL is used again.
- Python 3.10 (pyenv) has `lupa`, `makelove` and Pillow. Tests:
  `python tst/run.py`.
- Syntax check all Lua quickly with lupa `compile` (no `luac` here).
- LÖVE 11.5 is at `C:/Program Files/LOVE`. Run the game with
  `"C:/Program Files/LOVE/lovec.exe" .` from the repo root (console build,
  prints Lua errors to the terminal).
- Web build: `python -m makelove lovejs`, then
  `python tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`,
  unzip into `makelove-build/html`, serve that folder with
  `python -m http.server 8000`, open `http://localhost:8000/morphis/`.
  Stop the server afterwards or the next `rm -rf makelove-build` fails with
  "device busy".
- Browser check: node 22 with Playwright 1.64 (chromium installed under
  `%LOCALAPPDATA%/ms-playwright`). `node tools/web_shot.js out.png` loads the
  served page, waits 8 s, and screenshots it; it needs `playwright` resolvable
  from where it runs (`npm i playwright@1.64.0` in a scratch folder works).
  The page has two canvases, so click by page coordinates, not by locator.
  Clicking anywhere on the title starts the game; click the MUTE button to
  focus the canvas without starting. Keep runs short.
- `gh` is logged in as micahlagrange, so push and Actions checks work.

## Local workflow (first session's Linux container, for reference)

- Tests: `python3 tst/run.py` (luaunit under lupa, Lua 5.5 parser; keep code
  5.1 compatible). The level tests play every level with the real morphi AI.
- Web build locally: `makelove lovejs`, then
  `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`,
  unzip into `makelove-build/html`, serve with `python3 -m http.server 8000`
  from there, open `http://localhost:8000/morphis/`. `serve.sh` does this.
- Browser checks used Playwright from `/opt/node22/lib/node_modules/playwright`
  with chromium at `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`
  (`--no-sandbox --use-gl=swiftshader`). Phone emulation: viewport 852x393,
  hasTouch, isMobile, deviceScaleFactor 3.
- Font is LOVE's built in Vera Sans (`love.graphics.newFont(size)`), set to
  linear filtering because the game's default filter is nearest and the HUD
  is drawn under a fractional scale. `printFit` picks the largest font that
  fits a width.

## Architecture (LÖVE 11.4, love.js for web)

Pure logic (no love calls, unit tested): `src/constants.lua` (every tunable),
`util`, `rng`, `noise`, `world` (tiles, nodes, items, sites, storage, beds,
floors, rivers, reachability, enclosure, spend/refund), `jobs` (queue,
`takeNearest` with atomic claim), `pathfinder`, `worker` (the morphi AI),
`scoring`, `abilities` (tools: mine areas, floor, bin, bed, wall, door,
bridge lines, cancel/swap), `highscore` (keyed saves), `levels` (survival),
`arcade_levels` (arcade), `campaign` (loads either set, budgets, goals).
LÖVE side: `camera`, `audio`, `effects`, `view` (world drawing), `ui` (HUD,
title, panels, scaled layout, touch), `main.lua` (states and input).

Key rules in the current build:
- Diets: every morphi eats one food in survival and free play (Pupper
  steak, Woofoof fish, Twins cheese, Cwab chili, Blob candy, Ribbit grapes).
  Foragers pick any food into storage. Arcade morphis eat anything.
- Storage: floor spot (free, 1 item) and bin (1 log, 4 items, top-down art).
  Beds (2 logs) are woodwork built only by the lumberjack. Bridges 1 log per
  tile. Mining is free and only miners do it. Build marks can be cancelled or
  swapped with the tools. Build marks draw as ghosts.
- Jobs: nearest job the morphi can path to, claimed atomically. Unreachable
  jobs stay queued. Morale system (survival): hardships and hunger wear
  morphis down, at zero they leave. Hunger complaints are one per cooldown.
- A morphi standing on a tile that turns solid (a wall going up) steps to
  the nearest open tile (`Worker:unstick`).
- Modes: arcade, the default, six hand built levels (`src/arcade_levels.lua`);
  survival, retired but on the title, five levels (`src/levels.lua`); and
  free play (random map, rivers, seasons, migrants). Points spent vs par,
  three stars at par, progress persists per set (`arcadeN_*`, `levelN_*`).
- Arcade rules (`world.arcade`): no hunger, morale or breaks. Every morphi
  has one job (`ARCADE_ROLE`: Twins and Ribbit build, Pupper and Woofoof
  forage, Cwab and Blob mine) and eats anything, once, but only after the
  level's `needs` are met (`ARCADE_NEED_ORDER`: bins, floors, enclosed,
  binsInside; `World:arcadeReady`). The level is clear when everyone has
  eaten. Budgets per difficulty: `def.points.easy/normal/hard`,
  `Campaign.points`. Tools: SELECT MINE FLOOR BIN WALL DOOR BRIDGE
  (`TOOLS_ARCADE`; main swaps `ABILITY_ORDER` per mode and relays the HUD).
  Floors are living space (`World:markFloor`, capacity 0); walls block,
  doors pass. Enclosure (`World:enclosure`): fill from each floor over
  walkable tiles with doors shut, must never touch the map edge, and every
  floor must be reachable from camp, so a room needs a door. Stone and water
  count as walls. A builder stands on the camp side of a wall site
  (`World:reachableAvoiding`) so it never walls itself in. `Campaign.goals`
  is the live checklist, shown in the goal panel and in the bottom right of
  the HUD. `tst/arcade_test.lua` plays every level's obvious and par
  solutions with the real AI: obvious must fit the hard budget and cost at
  most half of easy; clever must come in under par.
- UI: HUD laid out in a virtual space scaled to the window (`UI:layout`),
  touch screens get a bigger font set and near 1:1 scale, quick buttons GOAL
  UNITS FOLLOW - + MUTE MENU, G opens the goal panel (levels open on it),
  U units list, pinch zoom, drag pan with SELECT, zoom capped to keep 20
  tiles on screen. Levels open zoomed to fit the whole map. Panels register
  their buttons in `UI.panelButtons`; main reads `ui:panelButtonAt`.
- Adding a morphi: a 16x16 walk sheet in `assets/images/morphis/`, a name in
  `MORPHI_SHEET_NAMES`, a diet in `MORPHI_DIET`, roles in `MORPHI_ROLE` and
  `ARCADE_ROLE`, the sheet in the role's `sheets` list, a food sprite in
  `FOOD_SPRITE`, a grid letter in `FOOD_CHAR`, and a level that lists it.

## itch settings the owner controls

For phones, the game's embed on itch should be "Click to launch in
fullscreen" with "Mobile friendly" ticked and landscape orientation. The
game fits any frame it is given but cannot change the itch frame.

## Known rough edges

- Portrait phones work but are small; the game hints to turn sideways.
- Gold has no sink since the memo tool was removed; it only scores.
- Arcade has no fail state as such; a stuck level offers RESTART LEVEL.
- The old design doc under `docs/human-resources-design-doc.md` describes
  the original corporate theme and is out of date.
