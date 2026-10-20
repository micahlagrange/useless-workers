#!/usr/bin/env python3
"""Copies the runs saved in the run viewer into the archive on this machine.

The run viewer (tools/stats_viewer.html, published as an Artifact) keeps
each pasted run in its database, collection "runs", one document per part
({name, part, parts, savedAt, text}); name is the run's file name,
<exported>-<first words of the note>-b<build>.json, which sorts in the
order the runs were made. Claude pulls them with ArtifactData (action list,
collection runs, out_dir stats/inbox), which saves each document as
stats/inbox/runs/<id>.json. This joins the parts and writes each run to the
archive under its name, skipping runs already there.

    python tools/stats_archive.py --clean
    python tools/stats_report.py ~/Documents/morphis-stats-archive/<name>

--clean deletes stats/inbox afterwards.
"""
import argparse
import glob
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('--inbox', default=os.path.join(ROOT, 'stats', 'inbox', 'runs'))
ap.add_argument('--archive', default=os.path.join(os.path.expanduser('~'), 'Documents', 'morphis-stats-archive'))
ap.add_argument('--clean', action='store_true')
args = ap.parse_args()

os.makedirs(args.archive, exist_ok=True)
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
    target = os.path.join(args.archive, safe)
    if len(parts) < total:
        print('incomplete: %s (%d of %d parts)' % (safe, len(parts), total))
        continue
    if os.path.exists(target):
        print('already archived: %s' % safe)
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
        target, meta.get('seed'), len(run.get('days', [])), meta.get('build'), meta.get('blurb', '')))

if args.clean:
    shutil.rmtree(os.path.dirname(args.inbox), ignore_errors=True)
