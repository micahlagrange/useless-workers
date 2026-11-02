#!/usr/bin/env python3
"""Write the build number into src/version.lua from the commit count.

The title screen shows `build` so a stale page can be told from a new one.
Nobody sets it by hand: CI runs this before makelove (the `pre_build` input of
the publish stub, on a full-history checkout), and a local test artifact is
built the same way. The committed file holds 0 so a plain checkout still runs.

Usage: python3 tools/stamp_version.py        (from anywhere in the repo)
Undo locally with `git checkout src/version.lua`.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, 'src', 'version.lua')
TEXT = """-- Shown in the title screen's corner, to tell which build a device is
-- running. Written by tools/stamp_version.py before a build (the commit
-- count of HEAD); the committed value is the fallback for a plain checkout.
return { build = %d }
"""


def commit_count():
    out = subprocess.run(['git', 'rev-list', '--count', 'HEAD'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return int(out.strip())


def main():
    n = commit_count()
    if n < 2:
        sys.exit('only %d commit visible: a shallow clone has no build number (fetch-depth: 0)' % n)
    with open(TARGET, 'w', encoding='utf-8', newline='\n') as f:
        f.write(TEXT % n)
    print('build %d -> %s' % (n, os.path.relpath(TARGET, ROOT)))


if __name__ == '__main__':
    main()
