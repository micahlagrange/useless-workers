#!/usr/bin/env python3
"""Make the love.js page fill the browser window, and make saves stick.

makelove's love.js template centres a fixed-size canvas under a heading. For
phones and itch.io's embed we want the canvas to be the whole viewport, with
no page scrolling or browser pinch-zoom, so the game gets a resize event
(SDL reads the canvas CSS size because the window is resizable) and lays its
HUD out for whatever screen it is on.

Phones never raise their keyboard for a canvas, so the page also gets a
hidden text field. The game prints '@@seed x y w h savedir seed' with
where the seed sits on screen; a tap there focuses the field inside the
tap (the only way iOS will show its keyboard) and every change is written
to savedir/webseed.txt, which the game reads, a newline meaning done. The
patched love.js hands the page its file system as window.__loveFS.

love.js keeps the save folder in IndexedDB but only writes it back from a
beforeunload handler, which a closing tab rarely lets finish. The patched
love.js also flushes every few seconds and whenever the page is hidden.

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


SEED_FIELD = r"""
<input id="seedField" type="text" autocomplete="off" autocorrect="off" autocapitalize="characters"
  spellcheck="false" maxlength="12" enterkeyhint="done"
  style="position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;font-size:16px;border:0;padding:0;">
<script type="text/javascript">
(function () {
  var field = document.getElementById('seedField');
  var rect = null, dir = null, seed = '';
  function clean(v) { return v.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12); }
  function send(text) {
    var fs = window.__loveFS;
    if (!fs || !dir) return;
    try { fs.mkdir(dir); } catch (e) {}
    try { fs.writeFile(dir + '/webseed.txt', text); } catch (e) {}
  }
  var log = console.log.bind(console);
  Module.print = function (t) {
    if (typeof t === 'string' && t.indexOf('@@') === 0) {
      var p = t.split(' ');
      if (p[0] === '@@seed') {
        if (p[1] === 'none') { rect = null; field.blur(); }
        else { rect = p.slice(1, 5).map(Number); dir = p[5]; seed = p[6] || ''; }
      } else if (p[0] === '@@seedblur') { field.blur(); }
      return;
    }
    log(t);
  };
  function inside(x, y) {
    return rect && x >= rect[0] && x <= rect[0] + rect[2] && y >= rect[1] && y <= rect[1] + rect[3];
  }
  window.addEventListener('touchend', function (e) {
    var t = e.changedTouches && e.changedTouches[0];
    if (t && inside(t.clientX, t.clientY)) {
      field.value = seed;
      field.focus();
    }
  }, true);
  field.addEventListener('input', function () {
    var v = clean(field.value);
    if (v !== field.value) field.value = v;
    send(v);
  });
  field.addEventListener('blur', function () { send(clean(field.value) + '\n'); });
  // typed keys belong to the field, not to the game as well
  ['keydown', 'keypress', 'keyup'].forEach(function (name) {
    field.addEventListener(name, function (e) {
      e.stopPropagation();
      if (name === 'keydown' && e.key === 'Enter') field.blur();
    });
  });
})();
</script>
"""

GAME_SCRIPT = '<script type="text/javascript" src="game.js"></script>'


def patch_html(html: str) -> str:
    if 'touch-action: none' in html:
        return html
    html = html.replace('</head>', STYLE, 1)
    if GAME_SCRIPT not in html:
        sys.exit('patch_lovejs: index.html has no game.js script to put the seed field before')
    html = html.replace(GAME_SCRIPT, SEED_FIELD + GAME_SCRIPT, 1)
    # keep the viewport from zooming on double tap
    html = html.replace('maximum-scale=1">', 'maximum-scale=1, user-scalable=no, viewport-fit=cover">', 1)
    return html


UNLOAD_HOOK = 'window.addEventListener("beforeunload",function(event){FS.syncfs(false,'
FLUSH = ('window.__loveFS=FS;(function(){var busy=false;function flush(){if(busy)return;busy=true;'
         'FS.syncfs(false,function(err){busy=false;if(err){Module["printErr"](err)}})}'
         'setInterval(flush,3000);'
         'document.addEventListener("visibilitychange",function(){if(document.hidden)flush()});'
         'window.addEventListener("pagehide",flush)})();')


def patch_lovejs(js: str) -> str:
    if 'setInterval(flush,3000)' in js:
        return js
    if UNLOAD_HOOK not in js:
        sys.exit('patch_lovejs: love.js has no beforeunload sync to hook; saves would not persist')
    return js.replace(UNLOAD_HOOK, FLUSH + UNLOAD_HOOK, 1)


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
