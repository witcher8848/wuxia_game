#!/usr/bin/env python3
"""Build a local investigation/combat candidate in isolation; never publish."""
import hashlib
import json
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
week = 5 if "--week5" in sys.argv else 4
version = f"0.{week}.0-week{week}-prototype"
save_directory = "ProjectWumingCharacterPrototype" if week == 5 else "ProjectWumingInvestigationPrototype"
binary = f"ProjectWumingWeek{week}"
git = lambda *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
out = root / f"builds/week{week}" / f"{version}_{git('rev-parse', '--short', 'HEAD')}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
out.mkdir(parents=True, exist_ok=False)
pack = out / f"{binary}.pck"


def checked(label, *args):
    label = label.replace("week4_candidate", f"week{week}_candidate")
    subprocess.run([sys.executable, str(root / "tools/run_checked.py"), label,
                    str(root / "tools/godot.sh"), *map(str, args)], cwd=root, check=True)


with tempfile.TemporaryDirectory(prefix=f"week{week}-stage-", dir=root / "builds") as temporary:
    stage = Path(temporary)
    shutil.copytree(root / "game", stage / "game", ignore=shutil.ignore_patterns("tests", "tools"))
    shutil.copytree(root / "assets/runtime", stage / "assets/runtime")
    shutil.copy2(root / "export_presets.cfg", stage / "export_presets.cfg")
    project = (root / "project.godot").read_text()
    for before, after in {
        'config/version="0.2.1-week2"': f'config/version="{version}"',
        'config/custom_user_dir_name="ProjectWuming"': f'config/custom_user_dir_name="{save_directory}"',
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
    checked("week4_candidate_export", "--headless", "--path", stage, "--export-release", "Windows Release", out / f"{binary}.exe")
    checked("week4_candidate_audit", "--headless", "--path", out, "--main-pack", pack, "--script", root / "tools/audit_pack.gd", "--", f"--week{week}-candidate")
    checked("week4_candidate_story", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_story_encounter.gd", "--", "--require-pack")
    checked("week4_candidate_onboarding", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_onboarding.gd", "--", "--require-pack")
    checked("week4_candidate_feedback", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_week4_feedback.gd", "--", "--require-pack")
    if week == 5:
        checked("week5_candidate_character", "--headless", "--path", out, "--main-pack", pack, "--script", root / "game/tests/test_character_pipeline.gd", "--", "--require-pack")
    subprocess.run([sys.executable, str(root / "tools/check_story_persistence.py"), "--pack", str(pack)], cwd=root, check=True)
    with (out / f"{binary}.exe").open("rb") as stream:
        if stream.read(2) != b"MZ": raise SystemExit("Missing PE header")
        stream.seek(60)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        if stream.read(4) != b"PE\0\0" or struct.unpack("<H", stream.read(2))[0] != 0x8664:
            raise SystemExit("Not Windows x86_64")
    shutil.copytree(root / "licenses", out / "licenses")
    playtest = (root / f"docs/week{week}_playtest.md").read_text()
    if week == 5:
        # The review bundle must remain readable after it is copied off-repo.
        # Ship the referenced render evidence, not links into the source tree.
        playtest = playtest.replace("[第五周评审追加记录](../11_week5_review.md#2026-10-08脸部反馈修订)",
                                    "[本包构建信息](./build_info.json)")

        def copy_review_image(match):
            relative = Path(match.group(1))
            source = (root / "docs/week5_evidence" / relative).resolve()
            if not source.is_relative_to((root / "docs/week5_evidence").resolve()) or not source.is_file():
                raise SystemExit(f"Missing/invalid review evidence: {relative}")
            destination = out / "review" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            return f"](./review/{relative.as_posix()})"

        playtest = re.sub(r"\]\(\./week5_evidence/([^\)]+\.png)\)", copy_review_image, playtest)
    (out / "PLAYTEST.md").write_text(playtest)
    # Local convenience launcher uses the installed, pinned runtime. It is not a
    # self-contained macOS app and has no relationship to the Windows EXE test.
    launcher = out / "Play-on-Mac.command"
    launcher.write_text('#!/bin/bash\nset -e\ncd "$(dirname "$0")"\nexec '
                        + shlex.quote(str(root / "tools/godot.sh"))
                        + f' --path "$PWD" --main-pack "$PWD/{binary}.pck"\n')
    launcher.chmod(0o755)
    if week == 5:
        preview = out / "Character-on-Mac.command"
        preview.write_text(launcher.read_text().rstrip() + ' res://game/presentation/characters/character_lab.tscn\n')
        preview.chmod(0o755)
    metadata = {
        "game_version": version, "purpose": f"local week{week} review; not Steam release",
        "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
        "staged_source_sha256": digest.hexdigest(), "target": "windows-x86_64 plus macOS PCK launcher using installed runtime",
        "engine": (root / ".godot-version").read_text().strip(),
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "save_directory": save_directory,
        "validated_on": "macOS automated PCK combat and two-process persistence; Windows hardware and human playtest pending",
    }
    (out / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    if week == 5:
        links = re.findall(r"\]\(([^\)]+)\)", playtest)
        for link in links:
            target = (out / link.split("#", 1)[0]).resolve()
            if not target.is_relative_to(out.resolve()) or not target.is_file():
                raise SystemExit(f"Review bundle link is not self-contained: {link}")
        print(f"PLAYTEST_LINKS_PASS files={len(links)}")
    (out / "validation").mkdir()
    labels = [f"week{week}_candidate_{name}" for name in ("import", "export", "audit", "story", "onboarding", "feedback")]
    labels += ["week4_pack_story_persistence_write", "week4_pack_story_persistence_read"]
    if week == 5: labels.append("week5_candidate_character")
    for label in labels:
        shutil.copy2(root / "builds/qa" / f"{label}.log", out / "validation" / f"{label}.log")
    sums = []
    for path in sorted(out.rglob("*")):
        if path.is_file():
            sums.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(out).as_posix()}")
    (out / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
print(f"WEEK{week}_CANDIDATE_PASS {out}")
