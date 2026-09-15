#!/usr/bin/env python3
"""Validate complete downloads against the official release SHA-512 manifest."""
import hashlib
import sys
from pathlib import Path

cache = Path(sys.argv[1])
sums = {}
for line in (cache / "SHA512-SUMS.txt").read_text().splitlines():
    digest, filename = line.split(maxsplit=1)
    sums[filename.lstrip("*")] = digest.lower()
for name in sys.argv[2:]:
    actual = hashlib.file_digest((cache / name).open("rb"), "sha512").hexdigest()
    if actual != sums.get(name):
        raise SystemExit(f"SHA512 mismatch: {name}; preserve the file for inspection and download a fresh copy.")
    print(f"SHA512_OK {name}")
