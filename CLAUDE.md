# Morphis

A LÖVE 11 game (Lua 5.1), played on desktop and in the browser through love.js.

## Working on it

- Push only to the branch `claude/game-jam-repo-analysis-ao9tmq`. Every push runs CI (`.github/workflows/build.yml`): tests, makelove builds, then butler pushes to https://multivoxmuse.itch.io/morphi about two minutes later. Itch can sit in "processing" and refuse new pushes for a while; it clears up by itself.
- `src/version.lua` holds the build number shown on the title screen. Set it to `git rev-list --count HEAD` + 1 in each commit you push, so a stale page can be told from a new one.
- Commit as Micah Turner <turner.micah@gmail.com>.
- Tests: `./test.sh` (luajit when installed, else `python3 tst/run.py`, which needs `pip install lupa`). Keep code Lua 5.1 compatible. `tst/arcade_test.lua` plays every arcade level's solutions with the real AI.

## Seeing it run

- Web build: makelove packs the committed tree, so commit first. Then `makelove lovejs` (or `python -m makelove lovejs`), `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`, and unzip it somewhere outside `makelove-build` (a server running inside it locks the folder on Windows). Serve that folder with `python3 -m http.server 8000`: the game is at `http://localhost:8000/morphis/`.
- Screenshots: `node tools/drive.js steps.json outdir [--phone]` plays the build headless with Playwright (software GL, no GPU needed) and saves the shots its steps ask for. love.js takes a click's position from the last mouse move, so the script hovers before each click. On the title screen, Enter twice starts the first level.
- Phone testing without itch: `tools/artifact_prep.sh <unzipped>/morphis out/` lays the build out for a claude.ai Artifact (which will not serve `.data` files), then publish `out/index.html` with the other files beside it.
