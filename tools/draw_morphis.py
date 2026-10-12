#!/usr/bin/env python3
"""Hand drawn walk cycles for Blob, Twins and Woofoof, pixel by pixel.

Each frame is a 16x16 grid of palette letters ('.' is clear). The sheets go
to assets/images/morphis/<name>-worker-walk.png, frames left to right; View
reads however many frames the sheet is wide. Pupper, Cwab and Ribbit are not
drawn here. Needs Pillow:  python tools/draw_morphis.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'images', 'morphis')

# Blob: a slime that hops. Neutral, squash, neutral, stretch.
BLOB_PAL = {
    'o': '#1f2580', 'b': '#3f48cc', 'l': '#7a83ea', 'd': '#2e36a8',
    'g': '#0ed145', 'k': '#0a0f40',
}
BLOB_NEUTRAL = [
    '................',
    '................',
    '................',
    '....oooooooo....',
    '...olllbbbbbo...',
    '..ollbbbbbbbbo..',
    '.olbbbbbbbbbbbo.',
    '.obbgkbbbbgkbbo.',
    'obbbggbbbbggbbbo',
    'obbbbbbbbbbbbbbo',
    'obbbbkbbbbkbbbbo',
    'obbbbbkkkkbbbbbo',
    'odbbbbbbbbbbbbdo',
    'oddbbbbbbbbbbddo',
    '.oddddddddddddo.',
    '..oooooooooooo..',
]
BLOB_SQUASH = [
    '................',
    '................',
    '................',
    '................',
    '................',
    '...oooooooooo...',
    '..ollllbbbbbbo..',
    '.olbbbbbbbbbbbo.',
    'obbbgkbbbbgkbbbo',
    'obbbggbbbbggbbbo',
    'obbbbkbbbbkbbbbo',
    'obbbbbkkkkbbbbbo',
    'odbbbbbbbbbbbbdo',
    'oddbbbbbbbbbbddo',
    'oddddddddddddddo',
    '.oooooooooooooo.',
]
BLOB_STRETCH = [
    '................',
    '.....oooooo.....',
    '....olllbbbo....',
    '...ollbbbbbbo...',
    '...olbbbbbbbo...',
    '..obbbbbbbbbbo..',
    '..obgkbbbbgkbo..',
    '..obggbbbbggbo..',
    '..obbbbbbbbbbo..',
    '..obbkbbbbkbbo..',
    '..obbbkkkkbbbo..',
    '..obbbbbbbbbbo..',
    '..odbbbbbbbbdo..',
    '..oddbbbbbbddo..',
    '...oddddddddo...',
    '....oooooooo....',
]

# Twins: one face, two halves. Cyan with blue lines, pink with purple.
TWINS_PAL = {
    'B': '#3f48cc', 'D': '#222ba4', 'c': '#8cfffb',
    'P': '#b83dba', 'Q': '#991c9b', 'p': '#ffaec8',
}
TWINS_BODY = [
    '..BB........PP..',
    '..BcB......PpP..',
    '.BccBBBBPPPPppP.',
    '.BccccccppppppP.',
    'BcccccccpppppppP',
    'BccDccccppppQppP',
    'BccDccccppppQppP',
    'BcccccccpppppppP',
    'BccDccccppppQppP',
    'BcccDDDDQQQQpppP',
    'BcccccccpppppppP',
    'BcccccccpppppppP',
    '.BccccccppppppP.',
    '..BBBBBBPPPPPP..',
]
TWINS_FEET = ('...BB......PP...', '...DD......QQ...')

# Woofoof: a fluffy blue dog, a white muzzle and a pink tongue.
WOOF_PAL = {
    'A': '#00a8f3', 'c': '#8cfffb', 'w': '#ffffff', 'k': '#000000',
    't': '#ffaec8', 'T': '#fe8eb2',
}
WOOF_BODY = [
    '..AAA......AAA..',
    '.AccAA....AAccA.',
    '.AcccAAAAAAcccA.',
    '.AccccccccccccA.',
    'AccccccccccccccA',
    'AcccwwwwwwwwcccA',
    'AccwkwwwwwwkwccA',
    'AccwkwwwwwwkwccA',
    'AccwwwwkkwwwwccA',
    'AccwwwkwwkwwwccA',
    'AcccwwwttwwwcccA',
    'AccccccTTccccccA',
    '.AccccccccccccA.',
    '..AAAAAAAAAAAA..',
]
WOOF_FEET = ('...cc......cc...', '...AA......AA...')


def walk(body, feet):
    """A front-on walk: stand, bob down with the left foot up, stand, bob
    down with the right foot up. body is 14 rows, feet two rows of 16."""
    top, sole = feet
    blank = '.' * 16
    stand = body + [top, sole]
    half = len(top) // 2
    left_up = [blank] + body + [blank[:half] + sole[half:]]
    right_up = [blank] + body + [sole[:half] + blank[half:]]
    return [stand, left_up, stand, right_up]


def hex_rgba(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


def save(name, frames, pal):
    sheet = Image.new('RGBA', (16 * len(frames), 16), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        assert len(frame) == 16, (name, i, 'rows', len(frame))
        for y, row in enumerate(frame):
            assert len(row) == 16, (name, i, y, row)
            for x, ch in enumerate(row):
                if ch != '.':
                    sheet.putpixel((i * 16 + x, y), hex_rgba(pal[ch]))
    path = os.path.join(OUT, name + '-worker-walk.png')
    sheet.save(path)
    print('wrote', os.path.normpath(path))


def main():
    save('blue', [BLOB_NEUTRAL, BLOB_SQUASH, BLOB_NEUTRAL, BLOB_STRETCH], BLOB_PAL)
    save('twins', walk(TWINS_BODY, TWINS_FEET), TWINS_PAL)
    save('woofoof', walk(WOOF_BODY, WOOF_FEET), WOOF_PAL)


if __name__ == '__main__':
    main()
