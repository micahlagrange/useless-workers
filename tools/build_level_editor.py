#!/usr/bin/env python3
"""Build a level editor that is one self-contained file.

    python tools/build_level_editor.py

Writes tools/level_editor_phone.html: tools/level_editor.html with the
sprites inlined and a copy of src/arcade_levels.lua built in, so it opens
with no server and no assets folder (send it to a phone, open it in a
browser, design, press Copy level, paste the level into a chat). Rebuild it
after the levels or the editor change.

With --bare it writes the same page without the <!doctype>/<html>/<head>/
<body> wrapper, for hosts that add their own (a claude.ai artifact).
"""
import base64
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, 'level_editor.html')
ASSETS = os.path.join(ROOT, 'assets', 'images')
FOODS = ['yp_ham.png', 'yp_tuna.png', 'yp_cheese.png', 'yp_chilipepper.png', 'yp_candy1.png', 'yp_grapes.png']
MORPHIS = ['pupper', 'woofoof', 'twins', 'cwab', 'blue', 'ribbit']


def data_uri(path):
    with open(path, 'rb') as f:
        return 'data:image/png;base64,' + base64.b64encode(f.read()).decode('ascii')


def build(bare):
    with open(SRC, encoding='utf-8') as f:
        html = f.read()
    assets = {'fruit/' + name: data_uri(os.path.join(ASSETS, 'fruit', name)) for name in FOODS}
    for m in MORPHIS:
        key = 'morphis/%s-worker-walk.png' % m
        assets[key] = data_uri(os.path.join(ASSETS, 'morphis', m + '-worker-walk.png'))
    with open(os.path.join(ROOT, 'src', 'arcade_levels.lua'), encoding='utf-8') as f:
        levels = f.read()
    embed = ('<script>\nwindow.STANDALONE = true;\nwindow.EMBEDDED_ASSETS = %s;\nwindow.GAME_LEVELS_LUA = %s;\n</script>\n'
             % (json.dumps(assets), json.dumps(levels)))
    # the embedded data goes in before the editor's own script reads it
    html = html.replace("<script>\n'use strict';", embed + "<script>\n'use strict';", 1)
    if bare:
        title = re.search(r'<title>.*?</title>', html).group(0)
        style = re.search(r'<style>.*?</style>', html, re.S).group(0)
        body = re.search(r'<body>(.*)</body>', html, re.S).group(1)
        html = title + '\n' + style + '\n' + body
    return html


def main():
    bare = '--bare' in sys.argv
    out = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else os.path.join(HERE, 'level_editor_phone.html')
    html = build(bare)
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(html)
    print('wrote %s (%d KB)' % (out, len(html) // 1024))


if __name__ == '__main__':
    main()
