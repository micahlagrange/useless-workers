#!/usr/bin/env python3
"""Free play balance: play the real game code for five seeds over three
years, with no player and with a simple one (a few floor spots by camp, a
bin and more spots each season), and print per season how fed the band is,
who leaves and arrives, the hardships by role and reason, and how each role
spends its time (work / food / rest / idle / sulk, and time spent hungry).

    python tools/balance_sim.py

About twenty seconds. Edit tools/balance_sim.lua for other seeds, years or
difficulties. Needs lupa, like the tests.
"""
import os
import sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path = "./?.lua;./?/init.lua;" .. package.path')
with open(os.path.join(ROOT, 'tools', 'balance_sim.lua'), encoding='utf-8') as f:
    lua.execute(f.read())
