#!/usr/bin/env python3
"""Source-only branch cold restarts, with an independently reaped writer per route.

The real GDScript exercises GameSession, ContentDB and SaveService. This harness
validates process order and its exact completion protocol; injected runners are
for orchestration unit tests only, not game or persistence evidence. No PCK,
native rendering or human-playtest claim is made by this source-only command.
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

PHASE_PREFIX = "BRANCH_CHOICE_SESSION_PHASE_PASS"
ERROR_OUTPUT = re.compile(
    r"SCRIPT ERROR:|ERROR:|Parse Error:|\bBRANCH_[A-Z_]*FAIL\b"
)
TIMEOUT_SECONDS = 60
CHOICES = ("home", "dock")
PHASES = ("write", "read")


def phase_pid(output: str, phase: str, choice: str, fixture: str) -> int:
    """Accept exactly one complete source marker, not substrings or stale runs."""
    if phase not in PHASES or choice not in CHOICES:
        raise ValueError("unknown branch phase or choice")
    markers = [line for line in output.splitlines() if PHASE_PREFIX in line]
    pattern = re.compile(
        rf"{PHASE_PREFIX} phase={re.escape(phase)} choice={re.escape(choice)} "
        rf"pid=([1-9]\d*) checks=([1-9]\d*) packed=false fixture={re.escape(fixture)}"
    )
    match = pattern.fullmatch(markers[0]) if len(markers) == 1 else None
    if match is None:
        raise ValueError(
            f"missing, duplicate, or invalid exact {choice}/{phase} completion marker"
        )
    return int(match.group(1))


def _isolated_fixture(fixture: str) -> bool:
    suffix = fixture.removeprefix("user://tests/")
    return bool(re.fullmatch(r"user://tests/branch_session_[A-Za-z0-9_]+", fixture)) and len(suffix) <= 96


def run_branch_persistence(
    root: Path,
    *,
    fixture: str | None = None,
    runner: Callable | None = None,
    output: TextIO | None = None,
) -> int:
    root = root.resolve()
    runner = subprocess.run if runner is None else runner
    output = sys.stdout if output is None else output
    fixture = fixture or f"user://tests/branch_session_{os.getpid()}_{time.time_ns()}"
    fixtures = {choice: f"{fixture}_{choice}" for choice in CHOICES}
    if not _isolated_fixture(fixture) or not all(_isolated_fixture(item) for item in fixtures.values()):
        print("BRANCH_PERSISTENCE_FAIL invalid isolated fixture", file=output, flush=True)
        return 1
    logdir = root / "builds/qa"
    try:
        logdir.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        print(f"BRANCH_PERSISTENCE_FAIL cannot create log directory: {error}", file=output, flush=True)
        return 1
    process_pids: list[int] = []
    for choice in CHOICES:
        branch_pids: list[int] = []
        current_fixture = fixtures[choice]
        for phase in PHASES:
            command = [str(root / "tools/godot.sh"), "--headless", "--path", str(root),
                       "--script", str(root / "game/tests/test_branch_choice_session.gd"), "--",
                       f"--fixture={current_fixture}", f"--phase={phase}", f"--choice={choice}"]
            logpath = logdir / f"week8_branch_{choice}_{phase}.log"
            try:
                # subprocess.run kills and reaps the child on TimeoutExpired.
                # A successful return is fully checked/logged before the next
                # process starts, never merely a queued writer launch.
                result = runner(command, cwd=root, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired as error:
                captured = error.stdout or ""
                if isinstance(captured, bytes):
                    captured = captured.decode(errors="replace")
                captured += (f"\nBRANCH_PERSISTENCE_TIMEOUT choice={choice} phase={phase} "
                             f"process terminated after {TIMEOUT_SECONDS} seconds\n")
                logpath.write_text(captured, encoding="utf-8")
                print(captured, end="", file=output, flush=True)
                return 124
            except OSError as error:
                captured = f"BRANCH_PERSISTENCE_FAIL choice={choice} phase={phase} launch: {error}\n"
                logpath.write_text(captured, encoding="utf-8")
                print(captured, end="", file=output, flush=True)
                return 127
            logpath.write_text(result.stdout, encoding="utf-8")
            print(result.stdout, end="", file=output, flush=True)
            if result.returncode or ERROR_OUTPUT.search(result.stdout):
                print(f"BRANCH_PERSISTENCE_FAIL choice={choice} phase={phase} process/output failed "
                      f"returncode={result.returncode}", file=output, flush=True)
                return result.returncode if result.returncode > 0 else 1
            try:
                pid = phase_pid(result.stdout, phase, choice, current_fixture)
            except ValueError as error:
                print(f"BRANCH_PERSISTENCE_FAIL {error}", file=output, flush=True)
                return 1
            if pid in process_pids:
                print("BRANCH_PERSISTENCE_FAIL writer/reader process identities reused",
                      file=output, flush=True)
                return 1
            process_pids.append(pid)
            branch_pids.append(pid)
            print(f"BRANCH_PERSISTENCE_PHASE_EXITED choice={choice} phase={phase} pid={pid} returncode=0",
                  file=output, flush=True)
        print(f"BRANCH_PERSISTENCE_ROUTE_PASS choice={choice} fixture={current_fixture} "
              f"writer_pid={branch_pids[0]} reader_pid={branch_pids[1]} packed=false "
              "(writer exited before reader launched)", file=output, flush=True)
    print(f"BRANCH_PERSISTENCE_RESTART_PASS choices=home,dock processes=4 packed=false fixture={fixture}",
          file=output, flush=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)  # Deliberately reject --pack: this stage is source-only.
    return run_branch_persistence(Path(__file__).resolve().parents[1])


if __name__ == "__main__":
    sys.exit(main())
