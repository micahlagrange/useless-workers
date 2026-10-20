#!/usr/bin/env python3
"""Turns stats EXPORTs sent from the Artifact test page into run files.

The test page writes each export into its database, collection "exports",
one document per part ({name, part, parts, createdAt, text}). Claude pulls
them onto this machine with ArtifactData (action list, collection exports,
out_dir stats/inbox), which saves each document as
stats/inbox/exports/<id>.json. This joins the parts and writes
stats/<name>, skipping runs already there.

    python tools/stats_inbox.py            # then: python tools/stats_report.py stats/<name>

Pass --clean to delete stats/inbox afterwards.
"""
import argparse
import glob
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('--inbox', default=os.path.join(ROOT, 'stats', 'inbox', 'exports'))
ap.add_argument('--out', default=os.path.join(ROOT, 'stats'))
ap.add_argument('--clean', action='store_true')
args = ap.parse_args()

runs = {}
for path in glob.glob(os.path.join(args.inbox, '*.json')):
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
    if not isinstance(doc, dict) or 'name' not in doc or 'text' not in doc:
        continue
    runs.setdefault(doc['name'], {})[int(doc.get('part', 1))] = doc

for name, parts in sorted(runs.items()):
    total = max(int(p.get('parts', 1)) for p in parts.values())
    # names come from the page: keep only the base name
    safe = os.path.basename(name).replace('..', '_')
    target = os.path.join(args.out, safe)
    if len(parts) < total:
        print('incomplete: %s (%d of %d parts)' % (safe, len(parts), total))
        continue
    if os.path.exists(target):
        print('already here: %s' % safe)
        continue
    text = ''.join(parts[i]['text'] for i in range(1, total + 1))
    try:
        run = json.loads(text)
    except ValueError as e:
        print('not a run file: %s (%s)' % (safe, e))
        continue
    with open(target, 'w', encoding='utf-8') as f:
        f.write(text)
    meta = run.get('meta', {})
    print('new: %s  seed %s  %d days  build %s  note: "%s"' % (
        os.path.relpath(target, ROOT), meta.get('seed'), len(run.get('days', [])), meta.get('build'), meta.get('blurb', '')))

if args.clean:
    shutil.rmtree(os.path.dirname(args.inbox), ignore_errors=True)
