#!/usr/bin/env python3
"""Godot may exit zero after script errors; require both clean output and exit code."""
import re
import subprocess
import sys
from pathlib import Path

label, *command = sys.argv[1:]
logdir = Path(__file__).resolve().parents[1] / "builds" / "qa"
logdir.mkdir(parents=True, exist_ok=True)
try:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
except subprocess.TimeoutExpired as error:
    output = error.stdout or b""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    output += "\nCHECK_TIMEOUT: process terminated after 180 seconds\n"
    (logdir / f"{label}.log").write_text(output)
    print(output, end="")
    raise SystemExit(124)
print(result.stdout, end="")
(logdir / f"{label}.log").write_text(result.stdout)
if result.returncode or re.search(r"(SCRIPT ERROR:|ERROR:|Parse Error:)", result.stdout):
    raise SystemExit(result.returncode or 1)
