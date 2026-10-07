#!/usr/bin/env python3
"""Build a local investigation/combat candidate in isolation; never publish."""
import hashlib
import json
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = "0.4.0-week4-prototype"
git = lambda *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
out = root / "builds/week4" / f"{version}_{git('rev-parse', '--short', 'HEAD')}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
out.mkdir(parents=True, exist_ok=False)
pack = out / "ProjectWumingWeek4.pck"


def checked(label, *args):
    subprocess.run([sys.executable, str(root / "tools/run_checked.py"), label,
                    str(root / "tools/godot.sh"), *map(str, args)], cwd=root, check=True)


with tempfile.TemporaryDirectory(prefix="week4-stage-", dir=root / "builds") as temporary:
    stage = Path(temporary)
    shutil.copytree(root / "game", stage / "game", ignore=shutil.ignore_patterns("tests", "tools"))
    shutil.copytree(root / "assets/runtime", stage / "assets/runtime")
    shutil.copy2(root / "export_presets.cfg", stage / "export_presets.cfg")
    project = (root / "project.godot").read_text()
    for before, after in {
        'config/version="0.2.1-week2"': f'config/version="{version}"',
        'config/custom_user_dir_name="ProjectWuming"': 'config/custom_user_dir_name="ProjectWumingInvestigationPrototype"',
    }.items():
        if project.count(before) != 1:
            raise SystemExit(f"Unexpected source setting: {before}")
        project = project.replace(before, after)
    (stage / "project.godot").write_text(project)
    digest = hashlib.sha256()
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(stage).as_posix().encode() + b"\0")
            digest.update(path.read_bytes())
    checked("week4_candidate_import", "--headless", "--path", stage, "--editor", "--import")
    checked("week4_candidate_export", "--headless", "--path", stage, "--export-release", "Windows Release", out / "ProjectWumingWeek4.exe")
    checked("week4_candidate_audit", "--headless", "--path", out, "--main-pack", pack, "--script", root / "tools/audit_pack.gd", "--", "--week4-candidate")
    checked("week4_candidate_story", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_story_encounter.gd", "--", "--require-pack")
    checked("week4_candidate_onboarding", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_onboarding.gd", "--", "--require-pack")
    checked("week4_candidate_feedback", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_week4_feedback.gd", "--", "--require-pack")
    subprocess.run([sys.executable, str(root / "tools/check_story_persistence.py"), "--pack", str(pack)], cwd=root, check=True)
    with (out / "ProjectWumingWeek4.exe").open("rb") as stream:
        if stream.read(2) != b"MZ": raise SystemExit("Missing PE header")
        stream.seek(60)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        if stream.read(4) != b"PE\0\0" or struct.unpack("<H", stream.read(2))[0] != 0x8664:
            raise SystemExit("Not Windows x86_64")
    shutil.copytree(root / "licenses", out / "licenses")
    shutil.copy2(root / "docs/week4_playtest.md", out / "PLAYTEST.md")
    # Local convenience launcher uses the installed, pinned runtime. It is not a
    # self-contained macOS app and has no relationship to the Windows EXE test.
    launcher = out / "Play-on-Mac.command"
    launcher.write_text('#!/bin/bash\nset -e\ncd "$(dirname "$0")"\nexec '
                        + shlex.quote(str(root / "tools/godot.sh"))
                        + ' --path "$PWD" --main-pack "$PWD/ProjectWumingWeek4.pck"\n')
    launcher.chmod(0o755)
    metadata = {
        "game_version": version, "purpose": "local week4 investigation/combat review; not Steam release",
        "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
        "staged_source_sha256": digest.hexdigest(), "target": "windows-x86_64 plus macOS PCK launcher using installed runtime",
        "engine": (root / ".godot-version").read_text().strip(),
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "save_directory": "ProjectWumingInvestigationPrototype",
        "validated_on": "macOS automated PCK combat and two-process persistence; Windows hardware and human playtest pending",
    }
    (out / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (out / "validation").mkdir()
    for label in ("week4_candidate_import", "week4_candidate_export", "week4_candidate_audit",
                  "week4_candidate_story", "week4_candidate_onboarding", "week4_candidate_feedback", "week4_pack_story_persistence_write", "week4_pack_story_persistence_read"):
        shutil.copy2(root / "builds/qa" / f"{label}.log", out / "validation" / f"{label}.log")
    sums = []
    for path in sorted(out.rglob("*")):
        if path.is_file():
            sums.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(out).as_posix()}")
    (out / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
print(f"WEEK4_CANDIDATE_PASS {out}")
