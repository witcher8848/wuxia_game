#!/usr/bin/env python3
"""Full Week8 source/PCK restart, each successful writer reaped before its reader."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def run(root: Path, pack: Path | None = None) -> int:
    base = f"week8_flow_{os.getpid()}_{time.time_ns()}"
    packed = "true" if pack else "false"
    if pack and not pack.is_file():
        print("WEEK8_PERSISTENCE_FAIL missing PCK")
        return 1
    logdir = root / "builds/qa"
    logdir.mkdir(parents=True, exist_ok=True)
    pids = []
    for choice in ("home", "dock"):
        fixture = f"user://tests/{base}_{choice}"
        for phase in ("write", "read"):
            command = [str(root / "tools/godot.sh"), "--headless", "--path", str(pack.parent if pack else root)]
            if pack:
                command += ["--main-pack", str(pack)]
            command += ["--script", str(root / "game/tests/test_week8_flow.gd"), "--",
                        "--fixture="+fixture, "--phase="+phase, "--choice="+choice]
            if pack: command += ["--require-pack"]
            try:
                result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=100)
            except subprocess.TimeoutExpired as error:
                print(f"WEEK8_PERSISTENCE_FAIL timeout choice={choice} phase={phase}")
                return 124
            except OSError as error:
                print(f"WEEK8_PERSISTENCE_FAIL {error}")
                return 127
            output = result.stdout + result.stderr
            (logdir / f"week8_full_{packed}_{choice}_{phase}.log").write_text(output)
            print(output, end="", flush=True)
            markers = [line for line in output.splitlines() if "WEEK8_FLOW_PASS" in line]
            pattern = (rf"WEEK8_FLOW_PASS checks=([1-9]\d*) failures=0 packed={packed} phase={phase} "
                       rf"choice={choice} pid=([1-9]\d*) fixture={re.escape(fixture)}")
            match = re.fullmatch(pattern, markers[0]) if len(markers) == 1 else None
            if result.returncode or re.search(r"SCRIPT ERROR:|ERROR:|Parse Error:|WEEK8_FLOW_FAIL", output) or not match:
                print(f"WEEK8_PERSISTENCE_FAIL phase={phase} choice={choice} exit={result.returncode}")
                return result.returncode if result.returncode > 0 else 1
            pid = int(match[2])
            if pid in pids:
                print("WEEK8_PERSISTENCE_FAIL PID reused")
                return 1
            pids.append(pid)
            print(f"WEEK8_PERSISTENCE_PHASE_EXITED choice={choice} phase={phase} pid={pid} returncode=0", flush=True)
    print(f"WEEK8_PERSISTENCE_PASS processes=4 choices=home,dock packed={packed} pids={','.join(map(str,pids))}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args()
    return run(Path(__file__).resolve().parents[1], args.pack.resolve() if args.pack else None)


if __name__ == "__main__":
    sys.exit(main())
