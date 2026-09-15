#!/usr/bin/env python3
import hashlib
import json
import struct
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

out = Path(sys.argv[1])
exe = out / "ProjectWuming.exe"
with exe.open("rb") as stream:
    if stream.read(2) != b"MZ":
        raise SystemExit("Export is not PE")
    stream.seek(60)
    stream.seek(struct.unpack("<I", stream.read(4))[0])
    if stream.read(4) != b"PE\0\0" or struct.unpack("<H", stream.read(2))[0] != 0x8664:
        raise SystemExit("Export is not Windows x86_64")
if not (out / "ProjectWuming.pck").is_file():
    raise SystemExit("PCK missing")
for forbidden in ["steam_appid.txt", ".godot", "source", "tests"]:
    if any(p.name == forbidden for p in out.rglob("*")):
        raise SystemExit(f"Forbidden packaged file: {forbidden}")
git = lambda *args: subprocess.check_output(["git", *args], text=True).strip()
metadata = {
    "game_version": "0.1.0-week1", "content_version": "0.1.0",
    "godot_version": Path(".godot-version").read_text().strip(),
    "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
    "built_at_utc": datetime.now(timezone.utc).isoformat(),
    "configuration": sys.argv[2], "target": "windows-x86_64",
}
(out / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")
checksums = []
for path in sorted(out.rglob("*")):
    if path.is_file() and path.name != "SHA256SUMS.txt":
        digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
        checksums.append(f"{digest}  {path.relative_to(out).as_posix()}")
(out / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n")
print("PACKAGE_CHECK_PASS architecture=x86_64")
