#!/usr/bin/env python3
"""Build the Wiflow Vietnamese gap catalog.

  build-i18n.py <po2lmo> <out-dir>

Reads rom/i18n/wiflow.vi.po (strings missing from the official LuCI vi
catalogs, plus Wiflow's own) and writes <out-dir>/wiflow.vi.lmo. LuCI loads
every *.vi.lmo of its i18n directory, so this file simply extends base.vi.lmo.
"""
import os, subprocess, sys
po2lmo, out = sys.argv[1:3]
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(out, exist_ok=True)
subprocess.check_call([po2lmo, os.path.join(here, "..", "rom", "i18n", "wiflow.vi.po"), os.path.join(out, "wiflow.vi.lmo")])
