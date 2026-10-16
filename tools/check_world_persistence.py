#!/usr/bin/env python3
"""Source-only Week 7 cold restart: reap the writer before launching the reader.

The GDScript uses actual GameSession/ContentDB/SaveService and additionally checks
the writer's receipt and distinct PID. This command proves the exit order and does not
export a PCK or claim packaged/native/keyboard validation.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Callable, TextIO

PHASE_PREFIX = "WEEK7_WORLD_SESSION_PHASE_PASS"
ERROR_OUTPUT = re.compile(r"SCRIPT ERROR:|ERROR:|Parse Error:|WEEK7_WORLD_SESSION_FAIL")
TIMEOUT_SECONDS = 60


def phase_pid(output: str, phase: str, fixture: str) -> int:
    """Require one complete positive source marker, never a substring/old marker."""
    markers = [line for line in output.splitlines() if PHASE_PREFIX in line]
    pattern = re.compile(
        rf"{PHASE_PREFIX} phase={re.escape(phase)} pid=([1-9]\d*) "
        rf"checks=([1-9]\d*) packed=false fixture={re.escape(fixture)}"
    )
    match = pattern.fullmatch(markers[0]) if len(markers) == 1 else None
    if match is None:
        raise ValueError(f"missing, duplicate, or invalid exact {phase} completion marker")
    return int(match.group(1))


def run_world_persistence(
    root: Path,
    *,
    fixture: str | None = None,
    runner: Callable | None = None,
    output: TextIO | None = None,
) -> int:
    root = root.resolve()
    runner = subprocess.run if runner is None else runner
    output = sys.stdout if output is None else output
    fixture = fixture or f"user://tests/world_session_{os.getpid()}_{time.time_ns()}"
    suffix = fixture.removeprefix("user://tests/")
    if not re.fullmatch(r"user://tests/world_session_[A-Za-z0-9_]+", fixture) or len(suffix) > 96:
        print("WORLD_PERSISTENCE_FAIL invalid isolated fixture", file=output, flush=True)
        return 1
    logdir = root / "builds/qa"
    logdir.mkdir(parents=True, exist_ok=True)
    phase_pids: list[int] = []
    for phase in ("write", "read"):
        command = [str(root / "tools/godot.sh"), "--headless", "--path", str(root),
                   "--script", str(root / "game/tests/test_week7_world_session.gd"), "--",
                   f"--fixture={fixture}", f"--phase={phase}"]
        logpath = logdir / f"week7_world_persistence_{phase}.log"
        try:
            # Synchronous run returns only after the child is reaped. In
            # particular, a reader is never started after writer failure.
            result = runner(command, cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired as error:
            captured = error.stdout or ""
            if isinstance(captured, bytes):
                captured = captured.decode(errors="replace")
            captured += f"\nWORLD_PERSISTENCE_TIMEOUT phase={phase} process terminated after {TIMEOUT_SECONDS} seconds\n"
            logpath.write_text(captured, encoding="utf-8")
            print(captured, end="", file=output, flush=True)
            return 124
        except OSError as error:
            captured = f"WORLD_PERSISTENCE_FAIL phase={phase} launch: {error}\n"
            logpath.write_text(captured, encoding="utf-8")
            print(captured, end="", file=output, flush=True)
            return 127
        logpath.write_text(result.stdout, encoding="utf-8")
        print(result.stdout, end="", file=output, flush=True)
        if result.returncode or ERROR_OUTPUT.search(result.stdout):
            print(f"WORLD_PERSISTENCE_FAIL phase={phase} process/output failed returncode={result.returncode}",
                  file=output, flush=True)
            return result.returncode if result.returncode > 0 else 1
        try:
            phase_pids.append(phase_pid(result.stdout, phase, fixture))
        except ValueError as error:
            print(f"WORLD_PERSISTENCE_FAIL {error}", file=output, flush=True)
            return 1
        print(f"WORLD_PERSISTENCE_PHASE_EXITED phase={phase} pid={phase_pids[-1]} returncode=0",
              file=output, flush=True)
    if len(set(phase_pids)) != 2:
        print("WORLD_PERSISTENCE_FAIL writer/reader process identities reused", file=output, flush=True)
        return 1
    print(f"WORLD_PERSISTENCE_RESTART_PASS fixture={fixture} writer_pid={phase_pids[0]} "
          f"reader_pid={phase_pids[1]} packed=false (writer exited before reader launched)",
          file=output, flush=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)  # Deliberately no --pack: this delivery is source-only.
    return run_world_persistence(Path(__file__).resolve().parents[1])


if __name__ == "__main__":
    sys.exit(main())
