#!/usr/bin/env python3
import hashlib
import json
import re
import struct
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
game_version = re.search(r'^config/version="([^"]+)"', (root / "project.godot").read_text(), re.M).group(1)
content_version = json.loads((root / "game/content/data/bootstrap.json").read_text())["content_version"]
if sys.argv[1:] == ["--version"]:
    print(game_version)
    raise SystemExit(0)
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
    "game_version": game_version, "content_version": content_version,
    "godot_version": Path(".godot-version").read_text().strip(),
    "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
    "built_at_utc": datetime.now(timezone.utc).isoformat(),
    "configuration": sys.argv[2], "target": "windows-x86_64",
}
# Identify a dirty working-tree build without pretending HEAD contains new files.
source_hash = hashlib.sha256()
source_paths = [root / "project.godot", root / "export_presets.cfg"]
source_paths += sorted(p for folder in [root / "game", root / "assets/runtime"] for p in folder.rglob("*") if p.is_file() and ".godot" not in p.parts and p.suffix not in [".import", ".translation", ".uid"])
for path in source_paths:
    source_hash.update(path.relative_to(root).as_posix().encode() + b"\0")
    source_hash.update(path.read_bytes())
metadata["source_sha256"] = source_hash.hexdigest()
(out / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")
checksums = []
for path in sorted(out.rglob("*")):
    if path.is_file() and path.name != "SHA256SUMS.txt":
        digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
        checksums.append(f"{digest}  {path.relative_to(out).as_posix()}")
(out / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n")
print("PACKAGE_CHECK_PASS architecture=x86_64")
