#!/usr/bin/env python3
"""Make the love.js page fill the browser window, and make saves stick.

makelove's love.js template centres a fixed-size canvas under a heading. For
phones and itch.io's embed we want the canvas to be the whole viewport, with
no page scrolling or browser pinch-zoom, so the game gets a resize event
(SDL reads the canvas CSS size because the window is resizable) and lays its
HUD out for whatever screen it is on.

love.js keeps the save folder in IndexedDB but only writes it back from a
beforeunload handler, which a closing tab rarely lets finish. The patched
love.js also flushes every few seconds and whenever the page is hidden.

A browser has no folder a player can open, so a file the game writes into
downloads/ in its save folder (the stats EXPORT) is handed to the browser
as a download and then deleted. A page can take it instead by defining
window.morphisExport(name, bytes, download) and returning true (the
Artifact test page does, see tools/artifact_bridge.html).

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


UNLOAD_HOOK = 'window.addEventListener("beforeunload",function(event){FS.syncfs(false,'
FLUSH = ('(function(){var busy=false;function flush(){if(busy)return;busy=true;'
         'FS.syncfs(false,function(err){busy=false;if(err){Module["printErr"](err)}})}'
         'setInterval(flush,3000);'
         'document.addEventListener("visibilitychange",function(){if(document.hidden)flush()});'
         'window.addEventListener("pagehide",flush)})();')
DOWNLOADS = ('(function(){setInterval(function(){var root="/home/web_user/love";var games;'
             'try{games=FS.readdir(root)}catch(e){return}'
             'games.forEach(function(g){if(g=="."||g=="..")return;var dir=root+"/"+g+"/downloads";var names;'
             'try{names=FS.readdir(dir)}catch(e){return}'
             'names.forEach(function(n){if(n=="."||n=="..")return;var p=dir+"/"+n;'
             'try{var data=FS.readFile(p);FS.unlink(p);var save=function(){var url=URL.createObjectURL(new Blob([data],{type:"application/json"}));'
             'var a=document.createElement("a");a.href=url;a.download=n;document.body.appendChild(a);a.click();a.remove();'
             'setTimeout(function(){URL.revokeObjectURL(url)},10000)};'
             'if(!(window.morphisExport&&window.morphisExport(n,data,save)))save()}catch(e){Module["printErr"](e)}})})},1000)})();')


def patch_lovejs(js: str) -> str:
    if 'setInterval(flush,3000)' in js:
        return js
    if UNLOAD_HOOK not in js:
        sys.exit('patch_lovejs: love.js has no beforeunload sync to hook; saves would not persist')
    return js.replace(UNLOAD_HOOK, FLUSH + DOWNLOADS + UNLOAD_HOOK, 1)


def patch_zip(path: str) -> None:
    with zipfile.ZipFile(path) as zin:
        entries = [(i, zin.read(i.filename)) for i in zin.infolist()]
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zout:
        for info, data in entries:
            if info.filename.endswith('index.html'):
                data = patch_html(data.decode('utf-8')).encode('utf-8')
            elif info.filename.endswith('love.js'):
                data = patch_lovejs(data.decode('utf-8')).encode('utf-8')
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
