#!/usr/bin/env python3
"""Build the active imagegen week-five review candidate without editing source.

The legacy week-four builder is imported only for its review-document collector.
PNG files are always read or copied byte-for-byte; this tool never processes
pixels. --preflight-only performs no export, import, or filesystem writes.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True  # Even a preflight without -B must not create tool caches.

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
MANIFEST_RESOURCE = "res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json"
ACTIVE_TEST = "game/tests/test_character_imagegen_pipeline.gd"
VERSION = "0.5.0-week5-prototype"
SAVE_DIRECTORY = "ProjectWumingCharacterPrototype"
BINARY = "ProjectWumingWeek5"
EXPECTED_CAPTURES = tuple(name + ".png" for name in (
    "walk_1x", "walk_2x", "walk_3x", "walk_phase_0", "walk_phase_1", "walk_phase_2", "walk_phase_3",
    "thrust", "slash", "guard", "hit", "down", "exploration", "battle"))
IMPORT_PARAMETERS = {
    "compress/mode": "0",
    "mipmaps/generate": "false",
    "process/fix_alpha_border": "false",
    "process/premult_alpha": "false",
    "process/size_limit": "0",
    "process/channel_remap/red": "0",
    "process/channel_remap/green": "1",
    "process/channel_remap/blue": "2",
    "process/channel_remap/alpha": "3",
}


def _module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


review = _module("week5_review_collector", TOOLS / "build_week4_candidate.py")
validator = _module("week5_manifest_validator", TOOLS / "validate_hero_manifest.py")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def import_parameters(path: Path) -> dict[str, str]:
    """Read Godot params without modifying an import configuration."""
    values = {}
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section == "params" and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() in values:
                raise ValueError(f"Duplicate texture import parameter: {path}: {key.strip()}")
            values[key.strip()] = value.strip()
    return values


def production_preflight(project_root: Path, *, source_root: Path | None = None) -> dict:
    """Check structure, original-byte provenance, and lossless import settings.

    Original candidates are matched by SHA, not by filenames or visual claims.
    This does NOT judge semantic regions, step alternation, hands or art quality.
    source_root may remain in the source project while project_root is a stage.
    """
    root = Path(project_root).resolve()
    sources = (root / "docs/art_reference" if source_root is None else Path(source_root)).resolve()
    manifest_path = root / MANIFEST_RESOURCE.removeprefix("res://")
    errors = validator.validate_manifest_file(manifest_path, root)
    if errors:
        raise ValueError("Active imagegen manifest is not ready:\n" + "\n".join(errors))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not sources.is_dir():
        raise ValueError(f"Original PNG source directory missing: {sources}")
    originals: dict[str, list[Path]] = {}
    for path in sorted(sources.rglob("*.png")):
        resolved = path.resolve()
        if not resolved.is_relative_to(sources):
            raise ValueError(f"Original PNG symlink escapes source directory: {path}")
        originals.setdefault(sha256(resolved), []).append(resolved)
    textures = sorted({frame["texture"] for frame in manifest["frames"]})
    records = []
    for resource in textures:
        runtime = root / resource.removeprefix("res://")
        digest = sha256(runtime)
        if digest not in originals:
            raise ValueError(f"No byte-identical original PNG for runtime texture: {resource}")
        config = Path(str(runtime) + ".import")
        if not config.resolve().is_relative_to((root / "assets/runtime/characters").resolve()):
            raise ValueError(f"Texture import configuration escapes runtime character directory: {resource}")
        parameters = import_parameters(config)
        for key, expected in IMPORT_PARAMETERS.items():
            if parameters.get(key) != expected:
                raise ValueError(f"Original-alpha import required: {resource}: {key} must be {expected}")
        info = validator.read_png_info(runtime)
        for frame in (record for record in manifest["frames"] if record["texture"] == resource):
            reference = frame.get("source_reference")
            prefix = "docs/art_reference/"
            if (not isinstance(reference, str) or not reference.startswith(prefix)
                    or "\\" in reference or any(part in ("", ".", "..") for part in reference.split("/"))):
                raise ValueError(f"Explicit canonical source_reference required: {resource}")
            original = (sources / reference.removeprefix(prefix)).resolve()
            if original not in originals[digest]:
                raise ValueError(f"source_reference does not identify byte-identical original: {resource}")
            source_size = frame.get("source_size")
            if (not isinstance(source_size, list) or len(source_size) != 2
                    or any(type(value) is not int for value in source_size)
                    or source_size != [info.width, info.height]):
                raise ValueError(f"source_size must match the original PNG dimensions: {resource}")
        records.append({
            "texture": resource, "sha256": digest, "size": [info.width, info.height],
            "originals": [str(path.relative_to(sources)) for path in originals[digest]],
            "import_sha256": sha256(config),
        })
    project = (root / "project.godot").read_text(encoding="utf-8")
    if not re.search(r"^textures/canvas_textures/default_texture_filter=0\s*$", project, re.M):
        raise ValueError("Project canvas textures must retain nearest filtering")
    return {
        "manifest": MANIFEST_RESOURCE,
        "manifest_sha256": sha256(manifest_path),
        "schema_version": manifest["schema_version"], "frame_count": manifest["frame_count"],
        "raw_pngs": records,
        "png_policy": "byte-identical originals; original alpha; GPU regions only; no PNG processing",
    }


def verify_stage_images(stage: Path, before: dict, source_root: Path) -> None:
    after = production_preflight(stage, source_root=source_root)
    if after["manifest_sha256"] != before["manifest_sha256"]:
        raise ValueError("Staging/import changed active manifest bytes")
    expected = {record["texture"]: record["sha256"] for record in before["raw_pngs"]}
    actual = {record["texture"]: record["sha256"] for record in after["raw_pngs"]}
    if expected != actual:
        raise ValueError("Staging/import changed original PNG bytes")


def stage_source_digest(stage: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(stage.rglob("*")):
        if path.is_file() and ".godot" not in path.relative_to(stage).parts:
            digest.update(path.relative_to(stage).as_posix().encode() + b"\0")
            digest.update(path.read_bytes())
    return digest.hexdigest()


def verify_pe(executable: Path) -> None:
    with executable.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("Missing Windows PE header")
        stream.seek(60)
        offset_bytes = stream.read(4)
        if len(offset_bytes) != 4:
            raise ValueError("Truncated Windows PE header")
        stream.seek(struct.unpack("<I", offset_bytes)[0])
        if stream.read(4) != b"PE\0\0" or stream.read(2) != b"\x64\x86":
            raise ValueError("Not Windows x86_64")


def write_checksums(output: Path) -> list[str]:
    sums = [f"{sha256(path)}  {path.relative_to(output).as_posix()}"
            for path in sorted(output.rglob("*"))
            if path.is_file() and path != output / "SHA256SUMS.txt"]
    (output / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
    return sums


def verify_active_log(path: Path, *, captures: int) -> None:
    """A zero exit or partial screenshots cannot stand in for complete testing."""
    contents = path.read_text(encoding="utf-8")
    markers = re.findall(r"^CHARACTER_IMAGEGEN_PIPELINE_PASS checks=(\d+) packed=true captures=(\d+)\s*$", contents, re.M)
    if len(markers) != 1 or int(markers[0][0]) <= 0 or int(markers[0][1]) != captures:
        raise ValueError(f"Complete active-production packed PASS marker missing/invalid: {path}")


def verify_capture_evidence(folder: Path) -> None:
    actual = {path.relative_to(folder).as_posix() for path in folder.rglob("*.png")}
    if actual != set(EXPECTED_CAPTURES):
        raise ValueError(f"Expected exact 14 packed-render PNGs; missing={sorted(set(EXPECTED_CAPTURES)-actual)} unexpected={sorted(actual-set(EXPECTED_CAPTURES))}")
    for name in EXPECTED_CAPTURES:
        info = validator.read_png_info(folder / name)
        if (info.width, info.height) != (640, 360):
            raise ValueError(f"Packed renderer evidence is not 640x360: {name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only", action="store_true", help="read-only; do not stage/import/export")
    arguments = parser.parse_args(argv)
    root = TOOLS.parent
    try:
        provenance = production_preflight(root)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"WEEK5_PREFLIGHT_FAIL {error}", file=sys.stderr)
        return 1
    if arguments.preflight_only:
        print("WEEK5_PREFLIGHT_PASS " + json.dumps(provenance, ensure_ascii=False, sort_keys=True))
        return 0
    for required in (ACTIVE_TEST, "tools/build_hero_imagegen_manifest.py"):
        if not (root / required).is_file():
            print(f"WEEK5_PREFLIGHT_FAIL required verifier missing: {required}", file=sys.stderr)
            return 1
    subprocess.run([sys.executable, str(root / "tools/build_hero_imagegen_manifest.py"), "--verify"], cwd=root, check=True)
    git = lambda *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    output = root / "builds/week5" / f"{VERSION}_imagegen_{git('rev-parse', '--short', 'HEAD')}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
    output.mkdir(parents=True, exist_ok=False)
    pack = output / f"{BINARY}.pck"
    logs = []

    def checked(label, *args, capture=False):
        logs.append(label)
        environment = None
        if capture:
            environment = dict(os.environ, WUXIA_CAPTURE_DIR=str(output / "evidence"))
        subprocess.run([sys.executable, str(root / "tools/run_checked.py"), label,
                        str(root / "tools/godot.sh"), *map(str, args)], cwd=root, env=environment, check=True)

    documents = review.collect_review_bundle(root, root / "docs/week5_playtest.md", output,
                                             redirects={root / "11_week5_review.md": output / "build_info.json"})
    with tempfile.TemporaryDirectory(prefix="week5-imagegen-stage-", dir=root / "builds") as temporary:
        stage = Path(temporary)
        shutil.copytree(root / "game", stage / "game", ignore=shutil.ignore_patterns("tests", "tools"))
        shutil.copytree(root / "assets/runtime", stage / "assets/runtime")
        shutil.copy2(root / "export_presets.cfg", stage / "export_presets.cfg")
        project = (root / "project.godot").read_text()
        for before, after in {
            'config/version="0.2.1-week2"': f'config/version="{VERSION}"',
            'config/custom_user_dir_name="ProjectWuming"': f'config/custom_user_dir_name="{SAVE_DIRECTORY}"',
        }.items():
            if project.count(before) != 1:
                raise ValueError(f"Unexpected source setting: {before}")
            project = project.replace(before, after)
        (stage / "project.godot").write_text(project)
        verify_stage_images(stage, provenance, root / "docs/art_reference")
        staged_digest = stage_source_digest(stage)
        checked("week5_imagegen_candidate_import", "--headless", "--path", stage, "--editor", "--import")
        verify_stage_images(stage, provenance, root / "docs/art_reference")
        checked("week5_imagegen_candidate_export", "--headless", "--path", stage,
                "--export-release", "Windows Release", output / f"{BINARY}.exe")
        checked("week5_imagegen_candidate_audit", "--headless", "--path", output, "--main-pack", pack,
                "--script", root / "tools/audit_pack.gd", "--", "--week5-candidate")
        for label, script in (("story", "test_story_encounter.gd"), ("onboarding", "test_onboarding.gd"),
                              ("feedback", "test_week4_feedback.gd"), ("character", "test_character_imagegen_pipeline.gd")):
            checked(f"week5_imagegen_candidate_{label}", "--headless", "--path", output, "--main-pack", pack,
                    "--script", root / "game/tests" / script, "--", "--require-pack")
            if label == "character":
                verify_active_log(root / "builds/qa/week5_imagegen_candidate_character.log", captures=0)
        checked("week5_imagegen_candidate_render", "--path", output, "--main-pack", pack,
                "--script", root / ACTIVE_TEST, "--", "--capture-imagegen", "--require-pack", capture=True)
        verify_active_log(root / "builds/qa/week5_imagegen_candidate_render.log", captures=14)
        verify_capture_evidence(output / "evidence")
        subprocess.run([sys.executable, str(root / "tools/check_story_persistence.py"), "--pack", str(pack)], cwd=root, check=True)
        logs += ["week4_pack_story_persistence_write", "week4_pack_story_persistence_read"]
        verify_pe(output / f"{BINARY}.exe")
        shutil.copytree(root / "licenses", output / "licenses")
        launcher_text = ('#!/bin/bash\nset -e\ncd "$(dirname "$0")"\nexec '
                         + shlex.quote(str(root / "tools/godot.sh"))
                         + f' --path "$PWD" --main-pack "$PWD/{BINARY}.pck"')
        for name, suffix in (("Play-on-Mac.command", ""),
                             ("Character-on-Mac.command", " res://game/presentation/characters/character_lab.tscn")):
            launcher = output / name
            launcher.write_text(launcher_text + suffix + "\n")
            launcher.chmod(0o755)
        metadata = {
            "game_version": VERSION, "purpose": "local week5 active-imagegen review; not Steam release",
            "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
            "staged_source_sha256": staged_digest, "active_character": provenance,
            "target": "windows-x86_64 plus macOS PCK launchers requiring installed runtime",
            "engine": (root / ".godot-version").read_text().strip(),
            "built_at_utc": datetime.now(timezone.utc).isoformat(), "save_directory": SAVE_DIRECTORY,
            "validated_on": "macOS automated packed exploration/battle/lab and real rendering; Windows hardware and human playtest pending",
        }
        (output / "build_info.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
        print(f"PLAYTEST_LINKS_PASS documents={len(documents)} local_links={review.validate_review_bundle(output, documents)}")
        (output / "validation").mkdir()
        for label in logs:
            shutil.copy2(root / "builds/qa" / f"{label}.log", output / "validation" / f"{label}.log")
        write_checksums(output)
    print(f"WEEK5_IMAGEGEN_CANDIDATE_PASS {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
