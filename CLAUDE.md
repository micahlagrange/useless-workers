# Morphis

A LÖVE 11 game (Lua 5.1), played on desktop and in the browser through love.js.

## Working on it

- Push only to the branch `claude/game-jam-repo-analysis-ao9tmq`. Every push runs CI (`.github/workflows/build.yml`): tests, makelove builds, then butler pushes to https://multivoxmuse.itch.io/morphi about two minutes later. Itch can sit in "processing" and refuse new pushes for a while; it clears up by itself.
- `src/version.lua` holds the build number shown on the title screen. Set it to `git rev-list --count HEAD` + 1 in each commit you push, so a stale page can be told from a new one.
- Commit as Micah Turner <turner.micah@gmail.com>.
- Tests: `./test.sh` (luajit when installed, else `python3 tst/run.py`, which needs `pip install lupa`). Keep code Lua 5.1 compatible. `tst/arcade_test.lua` plays every arcade level's solutions with the real AI.

## The backlog and how each kind ships

Micah files bugs and epics at https://claude.ai/artifact/KZhh7Y5bZffR6kcRafQaV6 (collection `items`: `kind` bug/feature/redesign, `priority` 1-4, `text`, `attachments` [{id, name, type, enc}], `status` open/working/testing/done, `note`, `build`). Work it top down: lowest `priority` number first, oldest first within one. Set `status` to working when you start, testing (with `note` and `build`) when it is on itch or a test page, and leave done to Micah. Read an attachment with the Artifact tool (`read`, `path` = its id); `enc: base64` means the file is base64 text to decode, `enc: text` means it was a text file stored as text/plain.

- **Bug**: fix on the main line. Publish (push) as soon as it is ready for a human to try: unit tests pass and a headless run shows the fix. Run sims fast (game speed up, `Worker:update` stepped in a loop, or a test that plays the level) rather than watching real time, and take only the screenshots that prove the fix.
- **Feature epic**: branch `epic/<slug>` off the main line. Each story is done on that branch and gets its own Artifact test page (`tools/artifact_prep.sh`), never an itch push. When every story is done, merge into the main line and push: that publishes.
- **Redesign epic**: branch `redesign/<slug>` with its own prototypes and test harnesses, kept apart from epics. Rebase onto the main line and push only once it meets the epic's "Ship when" bar.
- CI builds and tests every branch but only pushes the main line to itch.

## Seeing it run

- Web build: makelove packs the committed tree, so commit first. Then `makelove lovejs` (or `python -m makelove lovejs`), `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`, and unzip it somewhere outside `makelove-build` (a server running inside it locks the folder on Windows). Serve that folder with `python3 -m http.server 8000`: the game is at `http://localhost:8000/morphis/`.
- Screenshots: `node tools/drive.js steps.json outdir [--phone]` plays the build headless with Playwright (software GL, no GPU needed) and saves the shots its steps ask for. love.js takes a click's position from the last mouse move, so the script hovers before each click. On the title screen, Enter twice starts the first level.
- Phone testing without itch: `tools/artifact_prep.sh <unzipped>/morphis out/` lays the build out for a claude.ai Artifact (which will not serve `.data` files), then publish `out/index.html` with the other files beside it and `capabilities: {db: {}, user: {}}`.
- Stats EXPORTs from a test page land in that page's database, not a download. To get them onto this machine: ArtifactData `list` on the test page, collection `exports`, `out_dir` `stats/inbox`; then `python tools/stats_inbox.py --clean` writes each run to `stats/<name>` for `tools/stats_report.py`.
