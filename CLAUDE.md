# Morphis

A LÖVE 11 game (Lua 5.1), played on desktop and in the browser through love.js.

## Working on it

- `main` is the main line. Only an approved epic pull request is merged into it (see below); epic work goes on `epic/<slug>`. CI is the standard jam CI: `.github/workflows/publish.yml` and `epic.yml` are two small stubs that call the reusable workflows in https://github.com/micahlagrange/jam-ci. Every push builds and tests; a push to `main` also publishes the web build (`default_targets` in `makelove.toml`, web only) to https://multivoxmuse.itch.io/morphi. itch can sit in "processing" and refuse new pushes for a while; it clears up by itself.
- Never hand-edit the two stubs or add workflows: they are vended from the skills repo (`game-jam/scripts/jamci.mjs`). Change the test command or makelove inputs there and re-vend.
- `src/version.lua` holds the build number shown on the title screen. Set it to `git rev-list --count HEAD` + 1 in each commit you push to an epic branch, so a stale page can be told from a new one. (The merge commit is made by Actions and cannot stamp it.)
- Commit as Micah Turner <turner.micah@gmail.com>.
- Tests: `./test.sh` (luajit when installed, else `python3 tst/run.py`, which needs `pip install lupa`). Keep code Lua 5.1 compatible. `tst/arcade_test.lua` plays every arcade level's solutions with the real AI.

## The backlog and how it ships

Morphis is a standard jam game. Its backlog is GitHub issues in this repo with cards on its project board; the full flow, the review gate and who does what are in `~/.claude/skills/game-jam/references/epic-workflow.md` and the one-page version `~/.claude/skills/game-jam/references/sdlc.md`. Those win over this summary. In short:

- Micah writes an issue (description at most 50 words, `### Stories` as a checkbox list, at most 200 words). A bug is a small epic. A card in `backlog` is ready to build; a draft stays an issue he has not decided on.
- Build it in a fresh worktree from `origin` on `epic/<slug>`, merging `origin/main` in first. Fix `### Open review comments` first, then the stories, each proven with unit tests and a fast headless run (game speed up, `Worker:update` stepped in a loop, or a test that plays the level) rather than real time. Push the epic branch only, never `main`.
- Hand over with a test artifact built from the exact pushed commit (see Seeing it run), then fill the issue's `### Playtest`, `### How to test`, `### Test results`, `### Pull requests` and `### Announcement` sections and run `hub.mjs move --to review`. The review gate lists every gap.
- Micah plays it. To send it back he comments and moves the card to `claude-wip`. To ship it he approves the pull request on GitHub: Actions merges that commit, the merge push publishes to itch, then it verifies the page, announces on Discord and closes the issue. You do none of that.
- Never tick a story Micah has not seen built, never edit his text, never merge or approve, never move a card to `accepted`.
- Ambiguity is not a reason to stop: make a reasonable call and say so in a comment on the issue. Only a real decision for Micah goes under `### For Micah`.
- No itch devlogs: the skill rule is that none are written, draft or otherwise.

## Seeing it run

- Web build: makelove packs the committed tree, so commit first. Then `makelove lovejs` (or `python -m makelove lovejs`), `python3 tools/patch_lovejs.py makelove-build/lovejs/morphis-lovejs.zip`, and unzip it somewhere outside `makelove-build` (a server running inside it locks the folder on Windows). Serve that folder with `python3 -m http.server 8000`: the game is at `http://localhost:8000/morphis/`.
- Screenshots: `node tools/drive.js steps.json outdir [--phone]` plays the build headless with Playwright (software GL, no GPU needed) and saves the shots its steps ask for. love.js takes a click's position from the last mouse move, so the script hovers before each click. On the title screen, Enter twice starts the first level.
- Test artifacts (every epic in `review` has one): build from the committed tree as above (prefer building locally over downloading CI's artifact, which can fail on the account's egress limit), then `tools/artifact_prep.sh <unzipped>/morphis out/` lays the build out for a claude.ai Artifact (which will not serve `.data` files); publish `out/index.html` with the other files beside it: game.js, love.js, love.wasm and gamedata.wasm (the two wasm files as application/wasm), theme/bg.png and theme/love.css. Re-publish to the same artifact URL for a later build of the same epic.
- Name a test page `Morphis <EPIC> b<build> - <what's new>`: pass it as the third argument of `tools/artifact_prep.sh`, which sets the `<title>` tag, the only thing that names the artifact.

## Run stats

- A run's audit log (`src/stats.lua`) leaves the game as text: EXPORT (the DEV button on the top bar, or the screen at the end of any game: game over, end of year, level clear or failed) shows the JSON with COPY and DOWNLOAD; in a browser it sits in a selectable text box over the game. Micah pastes it into the run viewer, https://claude.ai/artifact/MkPjsiF2xNFFwgc3SRYMMf (source `tools/stats_viewer.html`, published with `capabilities: {db: {}, user: {}}`), which saves it in its database as `<exported>-<first words of the note>-b<build>.json`.
- To bring saved runs onto this machine: ArtifactData `list` on the run viewer, collection `runs`, `out_dir` `stats/inbox`; then `python tools/stats_archive.py --clean` writes each one to the archive, `C:/Users/sixst/Documents/morphis-stats-archive`, under that name. Read them there with `tools/stats_report.py`.
- Run exports, sims and graphs are never committed: `stats/` is ignored but for its README.

## Voice

Morphis are little blobs in a meadow: whimsical, soft and a bit silly, never fantasy, frontier or grim. Every player-facing string (labels, news, alerts, hints, milestones, the README, the Discord announcement) uses the meadow words: little blobs, the bunch, the home nest, stash, basket, nest, sticks, leaves, grass, shinies, digging, gatherer, digger, caretaker, grumbles, newcomers. Never use: dwarf, wilds, settler, migrant, lumber, chop, fell, log(s), stone, gold, ore, mine/mining/miner, camp, hardship, quit, the band. Internal identifiers (ROLE_LUMBERJACK, CARGO_LOGS, 'mine', world.breakroom, hires, quarter) may keep their old names until a story renames them; only what the player reads must change. `tst/words_test.lua` scans the string tables and a scripted free play log for the banned words.

## Old levels

The arcade and survival levels are kept for the coming hunting events (epic-hunting): `tst/arcade_test.lua` and `tst/levels_test.lua` play them with the real AI and must keep passing even after arcade leaves the title screen. Free play bests are saved as `meadowN.highscore` since the little blobs epic; the old `difficultyN.highscore` files are left unread.
