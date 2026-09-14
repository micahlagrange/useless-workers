#!/bin/bash
# Runs the unit tests. Uses luajit when installed (matches LÖVE), otherwise a
# lupa-based Python runner (pip install lupa).
set -e
cd "$(dirname "$0")"
if command -v luajit >/dev/null 2>&1; then
    for t in tst/*_test.lua; do
        printf '== %s\n' "$t"
        luajit "$t"
    done
else
    python3 tst/run.py
fi
