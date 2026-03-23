#!/usr/bin/env python3
import pathlib
import runpy

ROOT = pathlib.Path(__file__).resolve().parent
runpy.run_path(str(ROOT / "scripts" / "tools" / "fuse_bolt_epp.py"), run_name="__main__")
