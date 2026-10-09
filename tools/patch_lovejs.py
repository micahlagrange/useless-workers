#!/usr/bin/env python3
"""Make the love.js page fill the browser window.

makelove's love.js template centres a fixed-size canvas under a heading. For
phones and itch.io's embed we want the canvas to be the whole viewport, with
no page scrolling or browser pinch-zoom, so the game gets a resize event
(SDL reads the canvas CSS size because the window is resizable) and lays its
HUD out for whatever screen it is on.

Usage: patch_lovejs.py <path-to-lovejs-zip-or-index.html>
"""
import io
import sys
import zipfile

STYLE = """
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #17191a; }
  center, center > div { width: 100%; height: 100%; margin: 0; padding: 0; }
  h1, footer { display: none; }
  #canvas { width: 100vw; height: 100vh; touch-action: none; visibility: hidden; }
  #loadingCanvas { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); max-width: 100%; max-height: 100%; }
</style>
</head>"""


def patch_html(html: str) -> str:
    if 'touch-action: none' in html:
        return html
    html = html.replace('</head>', STYLE, 1)
    # keep the viewport from zooming on double tap
    html = html.replace('maximum-scale=1">', 'maximum-scale=1, user-scalable=no, viewport-fit=cover">', 1)
    return html


def patch_zip(path: str) -> None:
    with zipfile.ZipFile(path) as zin:
        entries = [(i, zin.read(i.filename)) for i in zin.infolist()]
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zout:
        for info, data in entries:
            if info.filename.endswith('index.html'):
                data = patch_html(data.decode('utf-8')).encode('utf-8')
            zout.writestr(info, data)
    with open(path, 'wb') as f:
        f.write(out.getvalue())


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    if path.endswith('.zip'):
        patch_zip(path)
    else:
        with open(path, encoding='utf-8') as f:
            html = f.read()
        with open(path, 'w', encoding='utf-8') as f:
            f.write(patch_html(html))
    print('patched', path)


if __name__ == '__main__':
    main()
