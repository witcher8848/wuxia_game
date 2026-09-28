#!/usr/bin/env python3
"""Build an isolated combat-review candidate; never rewrite the source project.

The staging copy promotes only the explicit prototype entry/fixture. Normal
release presets continue excluding game/tools and retain the exploration entry.
"""
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = "0.3.0-week3-prototype"
git = lambda *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
out = root / "builds" / "battle" / f"{version}_{git('rev-parse', '--short', 'HEAD')}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
out.mkdir(parents=True, exist_ok=False)


def checked(label, *args):
    subprocess.run([sys.executable, str(root / "tools/run_checked.py"), label,
                    str(root / "tools/godot.sh"), *map(str, args)], cwd=root, check=True)


with tempfile.TemporaryDirectory(prefix="week3-stage-", dir=root / "builds") as temporary:
    stage = Path(temporary)
    shutil.copytree(root / "game", stage / "game", ignore=shutil.ignore_patterns("tests", "tools"))
    shutil.copytree(root / "assets/runtime", stage / "assets/runtime")
    shutil.copy2(root / "export_presets.cfg", stage / "export_presets.cfg")
    project = (root / "project.godot").read_text()
    replacements = {
        'run/main_scene="res://game/presentation/main.tscn"': 'run/main_scene="res://game/presentation/battle/prototype_entry.tscn"',
        'config/version="0.2.1-week2"': f'config/version="{version}"',
        'config/custom_user_dir_name="ProjectWuming"': 'config/custom_user_dir_name="ProjectWumingCombatPrototype"',
    }
    for before, after in replacements.items():
        if project.count(before) != 1:
            raise SystemExit(f"Unexpected source setting: {before}")
        project = project.replace(before, after)
    (stage / "project.godot").write_text(project)
    source_entry = root / "game/tools/battle_lab"
    entry = (source_entry / "combat_lab.gd").read_text().replace(
        "res://game/tools/battle_lab/combat_encounter.json", "res://game/content/data/prototype_encounter.json")
    (stage / "game/presentation/battle/prototype_entry.gd").write_text(entry)
    scene = (source_entry / "combat_lab.tscn").read_text().replace(
        "res://game/tools/battle_lab/combat_lab.gd", "res://game/presentation/battle/prototype_entry.gd")
    (stage / "game/presentation/battle/prototype_entry.tscn").write_text(scene)
    shutil.copy2(source_entry / "combat_encounter.json", stage / "game/content/data/prototype_encounter.json")
    digest = hashlib.sha256()
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(stage).as_posix().encode() + b"\0")
            digest.update(path.read_bytes())
    checked("battle_candidate_import", "--headless", "--path", stage, "--editor", "--import")
    checked("battle_candidate_export", "--headless", "--path", stage, "--export-release", "Windows Release", out / "ProjectWumingBattle.exe")
    checked("battle_candidate_audit", "--headless", "--path", out, "--main-pack", out / "ProjectWumingBattle.pck", "--script", root / "tools/audit_pack.gd", "--", "--battle-candidate")
    checked("battle_candidate_smoke", "--headless", "--path", out, "--main-pack", out / "ProjectWumingBattle.pck", "--script", root / "tools/smoke_combat_pack.gd")
    with (out / "ProjectWumingBattle.exe").open("rb") as stream:
        if stream.read(2) != b"MZ": raise SystemExit("Missing PE header")
        stream.seek(60)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        if stream.read(4) != b"PE\0\0" or struct.unpack("<H", stream.read(2))[0] != 0x8664:
            raise SystemExit("Not Windows x86_64")
    shutil.copytree(root / "licenses", out / "licenses")
    shutil.copy2(root / "docs/week3_playtest.md", out / "PLAYTEST.md")
    metadata = {"game_version": version, "purpose": "standalone combat review, not Steam/release demo",
                "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
                "staged_source_sha256": digest.hexdigest(), "target": "windows-x86_64",
                "engine": (root / ".godot-version").read_text().strip(),
                "built_at_utc": datetime.now(timezone.utc).isoformat(),
                "validated_on": "macOS PCK smoke; Windows real hardware untested"}
    (out / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    sums = []
    for path in sorted(out.rglob("*")):
        if path.is_file(): sums.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(out).as_posix()}")
    (out / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
print(f"BATTLE_CANDIDATE_PASS {out}")
