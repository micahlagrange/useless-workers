#!/usr/bin/env python3
"""Tiled (mapeditor.org) support: a Morphis tileset, a blank map and the
game's arcade levels as Tiled maps.

    python tools/tiled/build_tiled.py

Writes, next to this script:
  morphis_tiles.png  the tiles, 16x16 each
  morphis.tsj        the tileset (JSON); every tile carries a `char` (a grid
                     letter) or a `mark` (a solution mark) property
  blank.tmj          an empty 22x8 level to start from
  levels/arcade_N.tmj  each level in src/arcade_levels.lua

A Morphis map has three tile layers: `terrain` (the grid), `obvious` and
`clever` (the two solutions, drawn with the mark tiles), and the level's
details as custom map properties: name, blurb, intro (strings), morphis and
needs (comma separated), easy, normal, hard and par (ints). Keep the tile
layer format as CSV (the default for .tmj). tools/level_editor.html imports
these maps and exports levels back to them. The tile order here must match
TILED_CHARS and TILED_MARKS in the editor.
"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FRUIT = os.path.join(ROOT, 'assets', 'images', 'fruit')
T = 16

# (grid letter, name), in tile id order
TILES = [('.', 'grass'), ('#', 'stone'), ('~', 'water'), ('B', 'camp'),
         ('k', 'steak'), ('f', 'fish'), ('c', 'cheese'), ('h', 'chili'), ('y', 'candy'), ('g', 'grapes'),
         ('T', 'tree'), ('G', 'gold ore'), ('b', 'bush'), ('W', 'wall'), ('D', 'door'), ('F', 'floor'),
         ('N', 'bin'), ('S', 'floor spot'), ('d', 'bed')]
MARKS = ['bridge', 'mine', 'floor', 'bin', 'wall', 'door']
FOOD_SPRITE = {'k': 'yp_ham.png', 'f': 'yp_tuna.png', 'c': 'yp_cheese.png', 'h': 'yp_chilipepper.png',
               'y': 'yp_candy1.png', 'g': 'yp_grapes.png'}
GRASS, STONE, WATER = (148, 163, 91), (109, 106, 100), (95, 143, 168)


def draw_tile(img, i, ch):
    d = ImageDraw.Draw(img)
    x0 = i * T
    base = STONE if ch in '#G' else WATER if ch == '~' else (201, 178, 122) if ch == 'B' else \
        (107, 79, 42) if ch == 'W' else (166, 130, 63) if ch == 'D' else GRASS
    d.rectangle([x0, 0, x0 + T - 1, T - 1], fill=base)
    if ch in '#G':
        d.line([x0, 0, x0 + T - 1, 0], fill=(140, 137, 130))
        d.rectangle([x0, T - 2, x0 + T - 1, T - 1], fill=(76, 74, 70))
    if ch == 'G':
        d.ellipse([x0 + 5, 5, x0 + 10, 10], fill=(230, 196, 64))
    if ch == 'B':
        d.rectangle([x0, 0, x0 + T - 1, T - 1], outline=(94, 74, 38))
    if ch == 'W':
        for r in range(3):
            d.rectangle([x0 + 1, r * 5 + 1, x0 + T - 2, r * 5 + 4], fill=(138, 106, 58))
    if ch == 'D':
        d.rectangle([x0 + 4, 2, x0 + 11, 14], fill=(107, 79, 42))
        d.point([x0 + 10, 8], fill=(230, 196, 64))
    if ch == 'T':
        d.rectangle([x0 + 7, 9, x0 + 8, 14], fill=(90, 58, 30))
        d.ellipse([x0 + 2, 1, x0 + 13, 11], fill=(47, 107, 42))
    if ch in FOOD_SPRITE or ch == 'b':
        d.ellipse([x0 + 2, 8, x0 + 13, 14], fill=(63, 122, 52))
        if ch in FOOD_SPRITE:
            sprite = Image.open(os.path.join(FRUIT, FOOD_SPRITE[ch])).convert('RGBA').resize((11, 11), Image.NEAREST)
            img.alpha_composite(sprite, (x0 + 2, 0))
    if ch in 'FS':
        d.rectangle([x0 + 2, 2, x0 + 13, 13], fill=(201, 166, 107), outline=(125, 98, 56))
    if ch == 'N':
        # the left half of a bin; the tile to its right is the other half
        d.rectangle([x0 + 1, 1, x0 + T - 1, 14], fill=(140, 107, 61))
        d.rectangle([x0 + 3, 3, x0 + T - 1, 12], fill=(42, 31, 16))
    if ch == 'd':
        d.rectangle([x0 + 2, 1, x0 + 13, 14], fill=(107, 79, 42))
        d.rectangle([x0 + 3, 2, x0 + 12, 13], fill=(238, 232, 208))
        d.rectangle([x0 + 3, 7, x0 + 12, 13], fill=(122, 160, 216))


def draw_mark(img, i, mark):
    """Solution marks: see-through, so the terrain shows under them."""
    over = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    if mark == 'bridge':
        d.rectangle([0, 2, T - 1, 13], fill=(138, 111, 63, 220))
        for y in (5, 8, 11):
            d.line([0, y, T - 1, y], fill=(80, 56, 28, 255))
    elif mark == 'mine':
        d.rectangle([1, 1, T - 2, T - 2], outline=(255, 153, 51, 255))
        d.line([3, 3, T - 4, T - 4], fill=(255, 153, 51, 255), width=2)
        d.line([T - 4, 3, 3, T - 4], fill=(255, 153, 51, 255), width=2)
    elif mark == 'floor':
        d.rectangle([2, 2, 13, 13], fill=(201, 166, 107, 200), outline=(125, 98, 56, 255))
    elif mark == 'bin':
        d.rectangle([1, 1, T - 1, 14], fill=(140, 107, 61, 220))
        d.rectangle([3, 3, T - 1, 12], fill=(42, 31, 16, 230))
        d.text((4, 2), '2', fill=(255, 255, 255, 255))
    elif mark == 'wall':
        for r in range(3):
            d.rectangle([1, r * 5 + 1, T - 2, r * 5 + 4], fill=(138, 106, 58, 220))
    elif mark == 'door':
        d.rectangle([4, 2, 11, 14], fill=(107, 79, 42, 230))
        d.point([10, 8], fill=(230, 196, 64, 255))
    img.alpha_composite(over, (i * T, 0))


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(data, f, indent=1)
        f.write('\n')


def tileset():
    n = len(TILES) + len(MARKS)
    img = Image.new('RGBA', (T * n, T), (0, 0, 0, 0))
    tiles = []
    for i, (ch, name) in enumerate(TILES):
        draw_tile(img, i, ch)
        tiles.append({'id': i, 'properties': [{'name': 'char', 'type': 'string', 'value': ch},
                                              {'name': 'label', 'type': 'string', 'value': name}]})
    for j, mark in enumerate(MARKS):
        i = len(TILES) + j
        draw_mark(img, i, mark)
        tiles.append({'id': i, 'properties': [{'name': 'mark', 'type': 'string', 'value': mark}]})
    img.save(os.path.join(HERE, 'morphis_tiles.png'))
    write_json(os.path.join(HERE, 'morphis.tsj'), {
        'type': 'tileset', 'version': '1.10', 'tiledversion': '1.10.2', 'name': 'morphis',
        'tilewidth': T, 'tileheight': T, 'tilecount': n, 'columns': n, 'margin': 0, 'spacing': 0,
        'image': 'morphis_tiles.png', 'imagewidth': T * n, 'imageheight': T, 'tiles': tiles,
    })


def tmj(level, tileset_path):
    """A level dict (the editor's shape) as a Tiled map."""
    grid = level['grid']
    w, h = len(grid[0]), len(grid)
    gid = {ch: i + 1 for i, (ch, _) in enumerate(TILES)}
    mgid = {m: len(TILES) + j + 1 for j, m in enumerate(MARKS)}
    terrain = [gid.get(ch, 1) for row in grid for ch in row]

    def marks(sol):
        data = [0] * (w * h)

        def put(x, y, m):
            if 1 <= x <= w and 1 <= y <= h:
                data[(y - 1) * w + (x - 1)] = mgid[m]
        for x1, y1, x2, y2 in sol.get('bridge', []):
            dx, dy = x2 - x1, y2 - y1
            if abs(dx) >= abs(dy):
                step = 1 if dx >= 0 else -1
                pts = [(x1 + i * step, y1) for i in range(abs(dx) + 1)]
            else:
                step = 1 if dy >= 0 else -1
                pts = [(x1, y1 + i * step) for i in range(abs(dy) + 1)]
            for x, y in pts:
                if grid[y - 1][x - 1] == '~':
                    put(x, y, 'bridge')
        for x1, y1, x2, y2 in sol.get('mine', []):
            for x in range(min(x1, x2), max(x1, x2) + 1):
                for y in range(min(y1, y2), max(y1, y2) + 1):
                    if grid[y - 1][x - 1] in '#G':
                        put(x, y, 'mine')
        for kind in ('floor', 'bin', 'wall', 'door'):
            for x, y in sol.get(kind, []):
                put(x, y, kind)
        return data

    def layer(lid, name, data, opacity=1):
        return {'id': lid, 'name': name, 'type': 'tilelayer', 'width': w, 'height': h, 'x': 0, 'y': 0,
                'opacity': opacity, 'visible': True, 'data': data}
    pts = level['points']
    props = [('name', 'string', level['name']), ('blurb', 'string', level['blurb']),
             ('intro', 'string', level['intro']), ('morphis', 'string', ','.join(level['morphis'])),
             ('needs', 'string', ','.join(k for k in ('bins', 'floors', 'enclosed', 'binsInside') if level['needs'].get(k))),
             ('easy', 'int', pts['easy']), ('normal', 'int', pts['normal']), ('hard', 'int', pts['hard']),
             ('par', 'int', level['par'])]
    return {
        'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
        'renderorder': 'right-down', 'width': w, 'height': h, 'tilewidth': T, 'tileheight': T,
        'infinite': False, 'nextlayerid': 4, 'nextobjectid': 1,
        'properties': [{'name': n, 'type': t, 'value': v} for n, t, v in props],
        'tilesets': [{'firstgid': 1, 'source': tileset_path}],
        'layers': [layer(1, 'terrain', terrain), layer(2, 'obvious', marks(level.get('obvious', {})), 0.8),
                   layer(3, 'clever', marks(level.get('clever', {})), 0.8)],
    }


def game_levels():
    """src/arcade_levels.lua, read with the same Lua the tests use."""
    from lupa import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = "%s/?.lua;" .. package.path' % ROOT.replace('\\', '/'))
    levels = lua.execute('return dofile("%s/src/arcade_levels.lua")' % ROOT.replace('\\', '/'))

    def tbl(t):
        if t is None:
            return None
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [tbl(t[k]) if hasattr(t[k], 'keys') else t[k] for k in sorted(keys)]
        return {k: (tbl(v) if hasattr(v, 'keys') else v) for k, v in t.items()}
    out = []
    for i in sorted(levels.keys()):
        lv = tbl(levels[i])
        for k in ('obvious', 'clever', 'needs'):
            if isinstance(lv.get(k), list) or lv.get(k) is None:
                lv[k] = {}
        out.append(lv)
    return out


def main():
    tileset()
    blank = {'name': 'New level', 'blurb': '', 'intro': '', 'morphis': ['pupper'],
             'points': {'easy': 10, 'normal': 6, 'hard': 3}, 'par': 2, 'needs': {},
             'grid': ['.' * 22] * 2 + ['..BB' + '.' * 18] * 2 + ['.' * 22] * 4}
    write_json(os.path.join(HERE, 'blank.tmj'), tmj(blank, 'morphis.tsj'))
    for i, lv in enumerate(game_levels(), 1):
        write_json(os.path.join(HERE, 'levels', 'arcade_%d.tmj' % i), tmj(lv, '../morphis.tsj'))
    print('wrote the tileset, blank.tmj and', len(game_levels()), 'levels in', HERE)


if __name__ == '__main__':
    main()
