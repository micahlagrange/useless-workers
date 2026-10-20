#!/bin/sh
# Lays out a built web version for publishing as a claude.ai Artifact, which
# will not serve a .data file: game.data goes up as gamedata.wasm and game.js
# is pointed at it.
#   tools/artifact_prep.sh makelove-build/html/morphis out/
# Publish out/index.html with game.js, love.js, love.wasm, gamedata.wasm and
# theme/ as its files (gamedata.wasm as application/wasm), and capabilities
# {db: {}, user: {}} so stats EXPORTs reach tools/stats_inbox.py.
set -e
src=$1
out=$2
mkdir -p "$out"
cp -r "$src/index.html" "$src/love.js" "$src/love.wasm" "$src/theme" "$out/"
cp "$src/game.data" "$out/gamedata.wasm"
sed "s/var REMOTE_PACKAGE_BASE = 'game.data';/var REMOTE_PACKAGE_BASE = 'gamedata.wasm';/" "$src/game.js" > "$out/game.js"
grep -q "REMOTE_PACKAGE_BASE = 'gamedata.wasm'" "$out/game.js" || { echo "game.js was not patched" >&2; exit 1; }
# stats EXPORTs go to the page's database for tools/stats_inbox.py; publish
# with capabilities {db: {}, user: {}}
bridge="$(dirname "$0")/artifact_bridge.html"
awk -v bridge="$bridge" '/<\/body>/ && !done { while ((getline line < bridge) > 0) print line; done = 1 } { print }' "$src/index.html" > "$out/index.html"
grep -q morphisExport "$out/index.html" || { echo "index.html has no export bridge" >&2; exit 1; }
