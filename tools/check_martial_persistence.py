#!/usr/bin/env python3
"""Two actual OS processes; writer clean exit is required before cold reader."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args()
    pack = args.pack.resolve() if args.pack else None
    if pack and not pack.is_file():
        parser.error("Pack file does not exist")
    fixture = f"user://tests/martial_persistence_{os.getpid()}_{time.time_ns()}"
    logdir = root / "builds" / "qa"
    logdir.mkdir(parents=True, exist_ok=True)
    phase_pids: list[int] = []
    for phase in ("write", "read"):
        launch = [str(root / "tools/godot.sh"), "--headless", "--path", str(pack.parent if pack else root)]
        if pack:
            launch += ["--main-pack", str(pack)]
        launch += ["--script", str(root / "game/tests/test_week6_martial_persistence.gd"), "--",
                   f"--fixture={fixture}", f"--phase={phase}"]
        if pack:
            launch.append("--require-pack")
        label = f"{'week6_pack_' if pack else 'week6_'}martial_persistence_{phase}"
        try:
            result = subprocess.run(launch, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=60)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            output += "\nMARTIAL_PERSISTENCE_TIMEOUT process terminated after 60 seconds\n"
            (logdir / f"{label}.log").write_text(output)
            print(output, end="")
            return 124
        (logdir / f"{label}.log").write_text(result.stdout)
        print(result.stdout, end="", flush=True)
        if result.returncode or re.search(r"SCRIPT ERROR:|ERROR:|Parse Error:|MARTIAL_PERSISTENCE_FAIL", result.stdout):
            return result.returncode or 1
        marker = re.compile(rf"^MARTIAL_PERSISTENCE_PHASE_PASS phase={phase} pid=(\d+) checks=(\d+) "
                            rf"packed={'true' if pack else 'false'} fixture={re.escape(fixture)}$", re.MULTILINE)
        matches = marker.findall(result.stdout)
        if len(matches) != 1 or int(matches[0][1]) < 1:
            print(f"MARTIAL_PERSISTENCE_FAIL missing or duplicate exact {phase} completion marker", flush=True)
            return 1
        phase_pids.append(int(matches[0][0]))
        print(f"MARTIAL_PERSISTENCE_PHASE_EXITED phase={phase} pid={phase_pids[-1]} returncode=0", flush=True)
        # subprocess.run has returned and reaped the writer before read starts.
    if len(set(phase_pids)) != 2:
        print("MARTIAL_PERSISTENCE_FAIL writer/reader process identities reused", flush=True)
        return 1
    print(f"MARTIAL_PERSISTENCE_RESTART_PASS fixture={fixture} "
          f"writer_pid={phase_pids[0]} reader_pid={phase_pids[1]} packed={'true' if pack else 'false'} "
          "(writer exited before reader launched)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
