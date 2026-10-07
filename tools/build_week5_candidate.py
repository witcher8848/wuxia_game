#!/usr/bin/env python3
"""Use the shared isolated candidate builder with week-five identity."""
import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    subprocess.run([sys.executable, str(Path(__file__).with_name("build_week4_candidate.py")), "--week5"], check=True)
