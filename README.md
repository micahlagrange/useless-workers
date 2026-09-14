# Human Resources

Control the environment. The employees will manage themselves. Badly.

A LÖVE2D jam game. You never control a worker. You dig, blast and bridge a
procedurally generated map so hungry AI employees can reach fruit and carry it
to the break room. Every ninety seconds a Quarterly Report grades you on output,
complaints and attrition. Keep them fed for four quarters.

Design doc: [docs/human-resources-design-doc.md](docs/human-resources-design-doc.md)

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

## Controls

- WASD or right-drag to pan, mouse wheel to zoom
- 1 to 5 pick a tool: select, dig, explode, bridge (drag across water), memo
- Select then click a worker to see who is complaining
- M mutes, ESC returns to the title

## History

This repo started as Morphi (Feb 2024), a job-queue worker sim that never
shipped. That code is kept under `legacy/morphi/`. Human Resources reuses its
job queue idea, the noise world from top-down-minecraft, and the tools, UI and
scoring from control-the-environment.
