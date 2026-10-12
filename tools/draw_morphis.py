#!/usr/bin/env python3
"""Walk cycles for Blob, Twins and Woofoof: slimes that plop along.

No legs. Each sheet is four 16x16 frames, left to right: rest, squash,
rest, stretch (leaning forward into the hop). Every frame faces RIGHT, with
the face sitting forward on the body; the game mirrors the sheet when a
morphi walks left (View draws with sx = -1), so the art must not be
symmetric or the turn would not show.

The body outline per frame is a list of (left, right) columns per row; the
face, ears and markings are painted on top relative to the body's top row,
so all four frames stay in step. Pupper, Cwab and Ribbit are not drawn
here. Needs Pillow:  python tools/draw_morphis.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'images', 'morphis')

# Body silhouettes: row -> (left, right), outline included.
REST = {3: (4, 11), 4: (3, 12), 5: (2, 13), 6: (1, 14), 7: (1, 14),
        8: (0, 15), 9: (0, 15), 10: (0, 15), 11: (0, 15), 12: (0, 15), 13: (0, 15),
        14: (1, 14), 15: (2, 13)}
SQUASH = {6: (3, 12), 7: (2, 13), 8: (1, 14),
          9: (0, 15), 10: (0, 15), 11: (0, 15), 12: (0, 15), 13: (0, 15), 14: (0, 15),
          15: (1, 14)}
# taller, narrower, the top leaning one pixel forward
STRETCH = {1: (6, 11), 2: (5, 12), 3: (4, 13), 4: (3, 13),
           5: (2, 13), 6: (2, 13), 7: (2, 13), 8: (2, 13), 9: (2, 13), 10: (2, 13),
           11: (2, 13), 12: (2, 13), 13: (2, 13), 14: (3, 12), 15: (4, 11)}
FRAMES = [('rest', REST), ('squash', SQUASH), ('rest', REST), ('stretch', STRETCH)]


def hex_rgba(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


class Frame:
    def __init__(self, shape):
        self.shape = shape
        self.px = {}
        self.top = min(shape)
        self.bottom = max(shape)

    def inside(self, x, y):
        span = self.shape.get(y)
        return span is not None and span[0] <= x <= span[1]

    def edge(self, x, y):
        """On the outline: the silhouette's border."""
        if not self.inside(x, y):
            return False
        return not all(self.inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    def body(self, fill, outline, shade=None, light=None):
        for y, (l, r) in self.shape.items():
            for x in range(l, r + 1):
                if self.edge(x, y):
                    self.px[(x, y)] = outline(x) if callable(outline) else outline
                else:
                    c = fill(x) if callable(fill) else fill
                    if shade and y >= self.bottom - 2:
                        c = shade(x) if callable(shade) else shade
                    self.px[(x, y)] = c
        if light:
            # a shine on the upper back (left: the morphi faces right)
            l, r = self.shape[self.top + 1]
            for x in (l + 1, l + 2):
                self.px[(x, self.top + 1)] = light
            l2, _ = self.shape[self.top + 2]
            self.px[(l2 + 1, self.top + 2)] = light

    def set(self, x, y, c):
        if 0 <= x < 16 and 0 <= y < 16:
            self.px[(x, y)] = c

    def face_row(self, kind):
        # eyes sit a little lower on a squash, higher on a stretch
        return self.top + {'rest': 4, 'squash': 3, 'stretch': 5}[kind]

    def forward(self, y):
        """The rightmost inside column of row y."""
        return self.shape[y][1]


def blob(kind, shape):
    o, b, d, l, g, k = '#1f2580', '#3f48cc', '#2e36a8', '#7a83ea', '#0ed145', '#0a0f40'
    f = Frame(shape)
    f.body(b, o, d, l)
    ey = f.face_row(kind)
    fx = f.forward(ey)
    # two eyes looking right: green with the pupil on the forward side
    for ex in (fx - 7, fx - 3):
        f.set(ex, ey, g); f.set(ex + 1, ey, k)
        f.set(ex, ey + 1, g); f.set(ex + 1, ey + 1, g)
    # a small smile under and ahead of the eyes
    f.set(fx - 6, ey + 3, k)
    for x in range(fx - 5, fx - 2):
        f.set(x, ey + 4, k)
    f.set(fx - 2, ey + 3, k)
    return f


def twins(kind, shape):
    B, D, c = '#3f48cc', '#222ba4', '#8cfffb'
    P, Q, p = '#b83dba', '#991c9b', '#ffaec8'
    f = Frame(shape)
    split = 7  # cyan up to here, pink after: one body, two halves
    f.body(lambda x: c if x <= split else p, lambda x: B if x <= split else P,
           lambda x: '#6fd9d6' if x <= split else '#e893b0')
    # pointed cat ears, one on each half
    t = f.top
    l, r = shape[t]
    for (x, y, col) in ((l, t - 1, B), (l + 1, t - 1, B), (l, t - 2, B),
                        (r - 1, t - 1, P), (r, t - 1, P), (r, t - 2, P)):
        f.set(x, y, col)
    ey = f.face_row(kind)
    fx = f.forward(ey)
    # one eye in each half, the face turned forward
    e1, e2 = split, fx - 2
    for ex, col in ((e1, D), (e2, Q)):
        f.set(ex, ey, col); f.set(ex, ey + 1, col)
    # smile across the seam
    f.set(e1 + 1, ey + 3, D)
    for x in range(e1 + 2, e2):
        f.set(x, ey + 4, D if x <= split else Q)
    f.set(e2, ey + 3, Q)
    return f


def woofoof(kind, shape):
    A, c, w, k, t = '#00a8f3', '#8cfffb', '#ffffff', '#000000', '#ffaec8'
    f = Frame(shape)
    f.body(c, A, '#6fd9e8', '#d8fffd')
    top = f.top
    l, r = shape[top]
    # floppy ears: the back one droops, the front one perks up
    for (x, y) in ((l, top - 1), (l + 1, top - 1), (l - 1, top), (l - 1, top + 1)):
        f.set(x, y, A)
    for (x, y) in ((r - 1, top - 1), (r, top - 1), (r, top - 2), (r + 1, top - 1)):
        f.set(x, y, A)
    ey = f.face_row(kind)
    fx = f.forward(ey + 2)
    # a white muzzle out front, nose at the tip, a pink tongue
    for y in range(ey + 1, ey + 4):
        for x in range(fx - 6, fx):
            if f.inside(x, y) and not f.edge(x, y):
                f.set(x, y, w)
    f.set(fx - 6, ey, k)          # back eye
    f.set(fx - 2, ey, k)          # front eye
    f.set(fx - 1, ey + 1, k)      # nose
    f.set(fx - 3, ey + 2, k)
    f.set(fx - 4, ey + 2, k)      # mouth
    f.set(fx - 3, ey + 3, t)      # tongue
    return f


def save(name, painter):
    sheet = Image.new('RGBA', (16 * len(FRAMES), 16), (0, 0, 0, 0))
    for i, (kind, shape) in enumerate(FRAMES):
        frame = painter(kind, shape)
        for (x, y), col in frame.px.items():
            if 0 <= x < 16 and 0 <= y < 16:
                sheet.putpixel((i * 16 + x, y), hex_rgba(col))
    path = os.path.join(OUT, name + '-worker-walk.png')
    sheet.save(path)
    print('wrote', os.path.normpath(path))


def main():
    save('blue', blob)
    save('twins', twins)
    save('woofoof', woofoof)


if __name__ == '__main__':
    main()
