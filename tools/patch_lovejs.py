#!/usr/bin/env python3
"""Make the love.js page fill the browser window, and make saves stick.

makelove's love.js template centres a fixed-size canvas under a heading. For
phones and itch.io's embed we want the canvas to be the whole viewport (less
the safe-area insets, where an Artifact viewer's top bar sits), with
no page scrolling or browser pinch-zoom, so the game gets a resize event
(SDL reads the canvas CSS size because the window is resizable) and lays its
HUD out for whatever screen it is on.

love.js keeps the save folder in IndexedDB but only writes it back from a
beforeunload handler, which a closing tab rarely lets finish. The patched
love.js also flushes every few seconds and whenever the page is hidden.

A browser has no folder a player can open, so a stats EXPORT the game
writes into exports/ in its save folder is shown in a text box over the
game, where it can be selected, copied or downloaded, to paste into the run
viewer. Closing the box deletes the file, and the game leaves its export
screen; the game deleting it (DONE) closes the box.

Usage: patch_lovejs.py <path-to-lovejs-zip-or-index.html>
"""
import io
import sys
import zipfile

STYLE = """
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #17191a; }
  /* the game fills what is left inside the safe area: a phone's notch and
     home bar, or the bar a claude.ai Artifact viewer puts on top */
  html { box-sizing: border-box; padding: env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px); }
  center, center > div { width: 100%; height: 100%; margin: 0; padding: 0; }
  h1, footer { display: none; }
  #canvas { display: block; width: 100%; height: 100%; touch-action: none; visibility: hidden; }
  #loadingCanvas { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); max-width: 100%; max-height: 100%; }
  #mx { position: fixed; z-index: 10; left: 0; right: 0; bottom: 0; display: flex; justify-content: center;
    padding: 12px max(12px, env(safe-area-inset-right, 0px)) max(12px, env(safe-area-inset-bottom, 0px)) max(12px, env(safe-area-inset-left, 0px)); }
  #mx[hidden] { display: none; }
  #mx .box { width: 100%; max-width: 760px; background: #1e2117; border: 1px solid #b6d36a; border-radius: 4px; padding: 10px; display: grid; gap: 8px;
    font: 14px/1.4 ui-monospace, Consolas, monospace; color: #e7ebd7; }
  #mx .name { color: #98a083; font-size: 12px; overflow-wrap: anywhere; }
  #mx textarea { width: 100%; box-sizing: border-box; height: 28vh; min-height: 90px; resize: vertical; background: #0d0f09; color: #e7ebd7;
    border: 1px solid #353a29; border-radius: 3px; padding: 8px; font: 12px/1.35 ui-monospace, Consolas, monospace; user-select: text; -webkit-user-select: text; }
  #mx .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  #mx button { font: 600 14px ui-monospace, Consolas, monospace; padding: 10px 16px; min-height: 44px; border-radius: 3px; cursor: pointer;
    background: #2a2f20; color: #e7ebd7; border: 1px solid #353a29; }
  #mx button.go { background: #b6d36a; color: #15170f; border-color: #b6d36a; }
  #mx .status { color: #b6d36a; font-size: 13px; }
</style>
</head>"""

# The EXPORT text box: shown by love.js's exports/ poll (EXPORTS below).
PANEL = """
<div id="mx" hidden><div class="box">
  <div class="name" id="mx-name"></div>
  <textarea id="mx-text" readonly aria-label="The run, as text to paste into the run viewer"></textarea>
  <div class="row">
    <button type="button" class="go" id="mx-copy">COPY</button>
    <button type="button" id="mx-download">DOWNLOAD</button>
    <button type="button" id="mx-close">CLOSE</button>
    <span class="status" id="mx-status" role="status"></span>
  </div>
</div></div>
<script>
(function () {
  var box = document.getElementById('mx'), ta = document.getElementById('mx-text'), status = document.getElementById('mx-status');
  var current = null;
  function say(t) { status.textContent = t; }
  function oldCopy() {
    ta.focus(); ta.select(); ta.setSelectionRange(0, ta.value.length);
    var ok = false; try { ok = document.execCommand('copy'); } catch (e) {}
    say(ok ? 'Copied.' : 'Selected: copy it with your browser.');
  }
  document.getElementById('mx-copy').onclick = function () {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(ta.value).then(function () { say('Copied.'); }, oldCopy);
    } else oldCopy();
  };
  document.getElementById('mx-download').onclick = function () {
    var url = URL.createObjectURL(new Blob([ta.value], { type: 'application/json' }));
    var a = document.createElement('a'); a.href = url; a.download = current.name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
    say('Downloading ' + current.name);
  };
  document.getElementById('mx-close').onclick = function () { if (current) current.close(); window.morphisExportPanel.hide(); };
  window.morphisExportPanel = {
    show: function (name, text, close) {
      current = { name: name, close: close };
      document.getElementById('mx-name').textContent = name + ' (' + text.length + ' characters)';
      ta.value = text; say(''); box.hidden = false;
    },
    hide: function () { current = null; box.hidden = true; ta.value = ''; },
  };
})();
</script>
</body>"""


def patch_html(html: str) -> str:
    if 'touch-action: none' in html:
        return html
    html = html.replace('</head>', STYLE, 1)
    html = html.replace('</body>', PANEL, 1)
    # keep the viewport from zooming on double tap
    html = html.replace('maximum-scale=1">', 'maximum-scale=1, user-scalable=no, viewport-fit=cover">', 1)
    return html


UNLOAD_HOOK = 'window.addEventListener("beforeunload",function(event){FS.syncfs(false,'
FLUSH = ('(function(){var busy=false;function flush(){if(busy)return;busy=true;'
         'FS.syncfs(false,function(err){busy=false;if(err){Module["printErr"](err)}})}'
         'setInterval(flush,3000);'
         'document.addEventListener("visibilitychange",function(){if(document.hidden)flush()});'
         'window.addEventListener("pagehide",flush)})();')
# Shows a file in exports/ of the save folder in the page's text box (PANEL),
# and hides the box once the file is gone.
EXPORTS = ('(function(){var shown=null;setInterval(function(){var panel=window.morphisExportPanel;if(!panel)return;'
           'var root="/home/web_user/love",found=null,games;try{games=FS.readdir(root)}catch(e){return}'
           'games.forEach(function(g){if(found||g=="."||g=="..")return;var dir=root+"/"+g+"/exports",names;'
           'try{names=FS.readdir(dir)}catch(e){return}'
           'names.forEach(function(n){if(!found&&n!="."&&n!="..")found={p:dir+"/"+n,n:n}})});'
           'if(found&&shown!==found.p){shown=found.p;var p=found.p;'
           'try{panel.show(found.n,FS.readFile(p,{encoding:"utf8"}),function(){try{FS.unlink(p)}catch(e){}})}catch(e){Module["printErr"](e)}}'
           'else if(!found&&shown){shown=null;panel.hide()}},400)})();')


def patch_lovejs(js: str) -> str:
    if 'setInterval(flush,3000)' in js:
        return js
    if UNLOAD_HOOK not in js:
        sys.exit('patch_lovejs: love.js has no beforeunload sync to hook; saves would not persist')
    return js.replace(UNLOAD_HOOK, FLUSH + EXPORTS + UNLOAD_HOOK, 1)


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
