#!/usr/bin/env python3
"""Runs every tst/*_test.lua file with luaunit inside a lupa Lua runtime.

The game targets Lua 5.1 (LuaJIT in LÖVE, plain 5.1 in love.js). lupa ships a
newer Lua, so anything that passes here and avoids 5.1-only or 5.4-only
features is safe. Use `luajit tst/foo_test.lua` when you have it installed.
"""
import glob
import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    print("lupa is missing: pip install lupa")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

failures = 0
files = sorted(glob.glob("tst/*_test.lua"))
if not files:
    print("no tests found")
    sys.exit(1)

for path in files:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = "./?.lua;./?/init.lua;" .. package.path')
    lua.execute("EXIT_CODE = nil; os.exit = function(code) EXIT_CODE = code or 0 end")
    print(f"== {path}")
    try:
        lua.execute(f'dofile("{path}")')
        code = lua.eval("EXIT_CODE")
        if code is None:
            code = 0
    except Exception as exc:  # noqa: BLE001
        print(f"   ERROR: {exc}")
        code = 1
    if code:
        failures += 1
        print(f"   FAILED ({path})")

print()
if failures:
    print(f"{failures} test file(s) failed")
    sys.exit(1)
print("all test files passed")
