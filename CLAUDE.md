# Morphis

A LÖVE 11 game (Lua 5.1), played on desktop and in the browser through love.js.

## Working on it

- Push only to the branch `main`. Every push runs CI (`.github/workflows/build.yml`): tests, makelove builds, then butler pushes to https://multivoxmuse.itch.io/morphi about two minutes later. Itch can sit in "processing" and refuse new pushes for a while; it clears up by itself.
- `src/version.lua` holds the build number shown on the title screen. Set it to `git rev-list --count HEAD` + 1 in each commit you push, so a stale page can be told from a new one.
- Commit as Micah Turner <turner.micah@gmail.com>.
- Tests: `./test.sh` (luajit when installed, else `python3 tst/run.py`, which needs `pip install lupa`). Keep code Lua 5.1 compatible. `tst/arcade_test.lua` plays every arcade level's solutions with the real AI.

## The backlog and how each kind ships

Micah files bugs and epics in the Jam Explorer, https://claude.ai/artifact/VejqPPeU1baL1Z7KsuQDHZ, which holds the backlogs of all his games: Morphis's are the documents in collection `items` with `jamId` `morphi` (`kind` bug/epic, `title`, `priority` 1-4, `status` open/working/testing/done, `note`, `build`; a bug adds `text` and `attachments` [{id, name, type, enc}], an epic adds `testStrategy` and `stories` [{id, text, done, note?, link?}]; items filed before 2026-10-20 may also carry an old `text`). Work it top down: lowest `priority` number first, oldest first within one. Statuses: open → working (you are on it) → deploying (pushed to the main line, with `deployedAt`, `build`, `note`, `testSteps`, `testUrl`) → done, which you set only after verifying the deployment: CI for that commit succeeded including its itch publish step, and the itch page serves the new build (its upload date is after `deployedAt`; the title screen's `build N` is the new one). Until then it stays at deploying with a note saying what is unverified. `testing` is Micah's own status for things he wants to try himself: never set it. Write what each story got in its `note`; Micah closes stories. Things only Micah can do go in collection `actions` as {text, jamId: `morphi`, itemId, createdAt, done: false}, never as a question you wait on. Read an attachment with the Artifact tool (`read`, `url` the Jam Explorer, `path` = its id); `enc: base64` means the file is base64 text to decode, `enc: text` means it was a text file stored as text/plain.

There are two kinds, bug and epic.

- **Bug**: fix on the main line. Publish (push) as soon as it is ready for a human to try: unit tests pass and a headless run shows the fix. Run sims fast (game speed up, `Worker:update` stepped in a loop, or a test that plays the level) rather than watching real time, and take only the screenshots that prove the fix.
- **Epic**: branch `epic/<slug>` off the main line, one story at a time. Iterate locally: unit tests, headless sims, the local web build and screenshots, following the epic's `testStrategy`. Publish nothing along the way: no Artifact test pages, no itch. When every story is closed, merge into the main line and push: that publishes.
- CI builds and tests every branch but only pushes the main line to itch.
- Every merge to the main line gets a **devlog post on the itch page** (game id 2546949), written for a player: a one or two sentence summary of the build; a paragraph or two more only when a change is big (how the new thing works, what to expect); up to 2 or 3 screenshots when they show something; then bulleted release notes, one specific change per line ("morphis face the correct way when mining", "initial farming mechanic introduced, may be buggy!"). Devlogs live on itch only, never in git: write the post as `devlog/build-N.md` (first line `# title`, `![](path)` lines for screenshots; the folder is gitignored scratch, do not commit it) and send it as a **draft**, never published, because Micah publishes his own devlogs: `node %USERPROFILE%\.claude\skills\game-jam\scripts\itchdevlog.mjs post --game 2546949 --post devlog/build-N.md --draft`, then tell him the draft is waiting. itch has no devlog API; the script drives the editor in its own signed-in Chromium profile, and `itchdevlog.mjs login` is the one-time sign-in only Micah can do. If the profile is not signed in, add a For Micah action asking for the login and keep the post text in the action; never type his password. Format details: the skill's `references/itch-devlog.md`.

## Seeing it run

- Web build: makelove packs the committed tree, so commit first. Then `makelove lovejs` (or `python -m makelove lovejs`), `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`, and unzip it somewhere outside `makelove-build` (a server running inside it locks the folder on Windows). Serve that folder with `python3 -m http.server 8000`: the game is at `http://localhost:8000/morphis/`.
- Screenshots: `node tools/drive.js steps.json outdir [--phone]` plays the build headless with Playwright (software GL, no GPU needed) and saves the shots its steps ask for. love.js takes a click's position from the last mouse move, so the script hovers before each click. On the title screen, Enter twice starts the first level.
- Phone testing without itch, only when Micah asks for it: `tools/artifact_prep.sh <unzipped>/morphis out/` lays the build out for a claude.ai Artifact (which will not serve `.data` files), then publish `out/index.html` with the other files beside it.
- Name a test page `Morphis <EPIC> b<build> - <what's new>`: pass it as the third argument of `tools/artifact_prep.sh`, which sets the `<title>` tag, the only thing that names the artifact.

## Run stats

- A run's audit log (`src/stats.lua`) leaves the game as text: EXPORT (the DEV button on the top bar, or the screen at the end of any game: game over, end of year, level clear or failed) shows the JSON with COPY and DOWNLOAD; in a browser it sits in a selectable text box over the game. Micah pastes it into the run viewer, https://claude.ai/artifact/MkPjsiF2xNFFwgc3SRYMMf (source `tools/stats_viewer.html`, published with `capabilities: {db: {}, user: {}}`), which saves it in its database as `<exported>-<first words of the note>-b<build>.json`.
- To bring saved runs onto this machine: ArtifactData `list` on the run viewer, collection `runs`, `out_dir` `stats/inbox`; then `python tools/stats_archive.py --clean` writes each one to the archive, `C:/Users/sixst/Documents/morphis-stats-archive`, under that name. Read them there with `tools/stats_report.py`.
- Run exports, sims and graphs are never committed: `stats/` is ignored but for its README.

## Voice

Morphis are little blobs in a meadow: whimsical, soft and a bit silly, never fantasy, frontier or grim. Every player-facing string (labels, news, alerts, hints, milestones, the README, devlogs) uses the meadow words: little blobs, the bunch, the home nest, stash, basket, nest, sticks, leaves, grass, shinies, digging, gatherer, digger, caretaker, grumbles, newcomers. Never use: dwarf, wilds, settler, migrant, lumber, chop, fell, log(s), stone, gold, ore, mine/mining/miner, camp, hardship, quit, the band. Internal identifiers (ROLE_LUMBERJACK, CARGO_LOGS, 'mine', world.breakroom, hires, quarter) may keep their old names until a story renames them; only what the player reads must change. `tst/words_test.lua` scans the string tables and a scripted free play log for the banned words.
