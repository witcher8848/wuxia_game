#!/usr/bin/env python3
"""A real save/quit/restart test: writer exits before a new reader is launched."""
import os
import argparse
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--pack", type=Path)
args = parser.parse_args()
pack = args.pack.resolve() if args.pack else None
if pack and not pack.is_file():
    raise SystemExit("Pack file does not exist")
fixture = f"user://tests/story_persistence_{os.getpid()}_{time.time_ns()}"
for phase in ("write", "read"):
    launch = ["--headless", "--path", str(pack.parent if pack else root)]
    if pack:
        launch += ["--main-pack", str(pack)]
    launch += ["--script", str(root / "game/tests/test_story_persistence.gd"), "--",
               f"--fixture={fixture}", f"--phase={phase}"]
    if pack:
        launch.append("--require-pack")
    subprocess.run([
        sys.executable, str(root / "tools/run_checked.py"),
        f"{'week4_pack_' if pack else ''}story_persistence_{phase}",
        str(root / "tools/godot.sh"), *launch,
    ], cwd=root, check=True)
    print(f"STORY_PERSISTENCE_PHASE_EXITED phase={phase} returncode=0", flush=True)
print(f"STORY_PERSISTENCE_RESTART_PASS fixture={fixture} (writer exited before reader launched)")
