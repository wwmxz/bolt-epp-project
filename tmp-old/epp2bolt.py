#!/usr/bin/env python3
import pathlib
import runpy

ROOT = pathlib.Path(__file__).resolve().parent
runpy.run_path(str(ROOT / "scripts" / "tools" / "epp2bolt.py"), run_name="__main__")
