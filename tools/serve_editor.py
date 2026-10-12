#!/usr/bin/env python3
"""Serve the level editor on your network so a phone can open it.

    python tools/serve_editor.py [port]

Serves the repo root (so the editor can show the game's sprites and load
src/arcade_levels.lua) and prints the address to open on a phone on the same
Wi-Fi. The editor's SAVE button writes src/arcade_levels.lua through this
server; it needs the token printed below (it is in the printed address), so
nobody else on the network can write the file. A copy of the old file goes to
src/arcade_levels.lua.bak first. Ctrl+C stops it.
"""
import http.server
import json
import os
import secrets
import socket
import sys
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LEVELS = os.path.join(ROOT, 'src', 'arcade_levels.lua')
TOKEN = secrets.token_urlsafe(9)


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))  # no packet is sent; it just picks the outward interface
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != '/save-arcade-levels':
            self.send_error(404)
            return
        if self.headers.get('X-Editor-Token') != TOKEN:
            self.send_error(403, 'wrong or missing token')
            return
        length = int(self.headers.get('Content-Length', 0))
        if length <= 0 or length > 1_000_000:
            self.send_error(400, 'bad length')
            return
        text = self.rfile.read(length).decode('utf-8')
        if 'return Levels' not in text or 'Levels[1]' not in text:
            self.send_error(400, 'that does not look like an arcade levels file')
            return
        if os.path.exists(LEVELS):
            with open(LEVELS, encoding='utf-8') as f:
                old = f.read()
            with open(LEVELS + '.bak', 'w', encoding='utf-8', newline='\n') as f:
                f.write(old)
        with open(LEVELS, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        body = json.dumps({'ok': True, 'path': os.path.relpath(LEVELS, ROOT)}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print('saved', LEVELS)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler)
    path = '/tools/level_editor.html#token=' + TOKEN
    print('Level editor', flush=True)
    print('  on this computer:  http://localhost:%d%s' % (port, path), flush=True)
    print('  on your phone:     http://%s:%d%s' % (lan_ip(), port, path), flush=True)
    print('  (same Wi-Fi; Windows may ask to let Python through the firewall)', flush=True)
    print('Ctrl+C to stop.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
