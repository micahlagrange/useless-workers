# Morphis levels in Tiled

[Tiled](https://www.mapeditor.org) is a free map editor (Windows, Mac, Linux).
These files let you draw arcade levels in it and bring them into the game
through `tools/level_editor.html`.

- `morphis.tsj` + `morphis_tiles.png`: the tileset. The first tiles are the
  map (grass, stone, water, camp, the six foods, tree, gold, bush, wall,
  door, floor, bin, floor spot, bed); the last six are solution marks
  (bridge, mine, floor, bin, wall, door).
- `blank.tmj`: an empty level to start from. `levels/arcade_N.tmj`: the
  game's levels.

A level has three tile layers:

- `terrain`: the map. Paint the camp as a 2x2 block. A bin is the bin tile
  on its left square with grass to its right.
- `obvious` and `clever`: the two solutions the tests play, in mark tiles.
  Mark every bridge tile over the water and every stone tile to mine.

The level's details are custom map properties (Map > Map Properties):
`name`, `blurb`, `intro`, `morphis` (comma separated: pupper, woofoof,
twins, cwab, blue, ribbit), `needs` (comma separated: bins, floors,
enclosed, binsInside), and `easy`, `normal`, `hard`, `par` (numbers).

Keep the tile layer format as CSV and the map finite. Then in the level
editor, Save & export > Import a Tiled map, check the level, and save or
copy it. The editor can also export any level as a .tmj for Tiled.

Regenerate everything here with `python tools/tiled/build_tiled.py`
(after changing the levels or the tiles).
