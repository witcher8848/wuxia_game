#!/usr/bin/env python3
"""Build a local investigation/combat candidate in isolation; never publish."""
import hashlib
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

LINK_TARGET = r'(?:<[^>\n]+>|(?:\\.|[^\s()\\]|\([^()\n]*\))+)'
INLINE_LINK = re.compile(r'(?P<prefix>\]\(\s*)(?P<target>' + LINK_TARGET
                         + r')(?P<suffix>(?:\s+(?:"[^"\n]*"|\'[^\'\n]*\'))?\s*\))')
REFERENCE_LINK = re.compile(r'(?P<prefix>^ {0,3}\[[^\]\n]+\]:[ \t]*)(?P<target>'
                            + LINK_TARGET + r')', re.M)
INLINE_CODE = re.compile(r'(`+).*?\1')
REVIEW_EXTENSIONS = {".md", ".txt", ".json", ".png", ".jpg", ".jpeg", ".gif",
                     ".webp", ".svg", ".mp4", ".avi", ".webm", ".pdf"}


def rewrite_markdown_links(contents, rewrite):
    """Rewrite inline/image/reference links, leaving code examples untouched."""
    result = []
    fence = None
    for line in contents.splitlines(keepends=True):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            run = marker.group(1)
            if fence is None:
                fence = (run[0], len(run))
            elif run[0] == fence[0] and len(run) >= fence[1]:
                fence = None
            result.append(line)
            continue
        if fence:
            result.append(line)
            continue

        def replace(match):
            target = match.group("target")
            angled = target.startswith("<")
            rewritten = rewrite(target[1:-1] if angled else target)
            return match.group("prefix") + ("<" + rewritten + ">" if angled else rewritten) + (match.groupdict().get("suffix") or "")

        # A reference definition must be handled as a whole, including its URL.
        if REFERENCE_LINK.match(line):
            result.append(REFERENCE_LINK.sub(replace, line))
            continue
        cursor = 0
        pieces = []
        for code in INLINE_CODE.finditer(line):
            pieces.append(INLINE_LINK.sub(replace, line[cursor:code.start()]))
            pieces.append(code.group())
            cursor = code.end()
        pieces.append(INLINE_LINK.sub(replace, line[cursor:]))
        result.append("".join(pieces))
    return "".join(result)


def local_link(link):
    parsed = urlsplit(link)
    if parsed.scheme or parsed.netloc:
        if parsed.scheme not in ("", "http", "https", "mailto", "tel"):
            raise ValueError(f"Unsupported review link scheme: {link}")
        return None
    if not parsed.path:
        return None  # Same-document anchors do not require another file.
    path = unquote(parsed.path)
    if Path(path).is_absolute() or "\\" in path:
        raise ValueError(f"Absolute/invalid review link: {link}")
    return path, ("?" + parsed.query if parsed.query else "") + ("#" + parsed.fragment if parsed.fragment else "")


def collect_review_bundle(project_root, source_document, output_dir, *, source_text=None, redirects=None):
    """Collect only linked review files outside the PCK, with a bounded source scope.

    Source paths and symlinks are resolved before any copying. The complete
    reference graph is preflighted first, so a bad link fails before export.
    Markdown cycles are deduplicated and all copied Markdown is rewritten.
    """
    project_root = Path(project_root).resolve()
    source_document = Path(source_document).resolve()
    output_dir = Path(output_dir).resolve()
    redirects = {Path(source).resolve(): Path(target).resolve()
                 for source, target in (redirects or {}).items()}
    destinations = {source_document: output_dir / "PLAYTEST.md"}
    documents = {}

    def safe_source(source):
        source = source.resolve()
        if not source.is_relative_to(project_root) or not source.is_file():
            raise ValueError(f"Missing/out-of-project review target: {source}")
        relative = source.relative_to(project_root)
        suffix = source.suffix.lower()
        allowed = (relative.parts[0] == "docs" and suffix in REVIEW_EXTENSIONS)
        allowed |= (relative.parts[0] == "tools" and suffix == ".gd")
        allowed |= (relative.parts[:2] in (("assets", "source"), ("assets", "runtime"))
                    and suffix in {".md", ".gd", ".png", ".json"})
        allowed |= (len(relative.parts) == 1 and suffix == ".md")
        if not allowed or any(part.startswith(".") for part in relative.parts):
            raise ValueError(f"Not an allowed review attachment: {relative}")
        return source

    def safe_destination(destination):
        destination = destination.resolve()
        if not destination.is_relative_to(output_dir):
            raise ValueError(f"Out-of-bundle review target: {destination}")
        return destination

    def collect(source, contents=None):
        source = safe_source(source)
        if source in documents or source.suffix.lower() != ".md":
            return
        documents[source] = None  # Mark first: documents can link in cycles.
        destination = safe_destination(destinations[source])

        def rewrite(link):
            local = local_link(link)
            if local is None:
                return link
            relative, suffix = local
            target = safe_source(source.parent / relative)
            if target in redirects:
                packaged = safe_destination(redirects[target])
                suffix = ""  # A historical document anchor is not a JSON anchor.
            else:
                packaged = safe_destination(output_dir / "review" / target.relative_to(project_root))
                destinations.setdefault(target, packaged)
                packaged = safe_destination(destinations[target])
                collect(target)
            rewritten = Path(os.path.relpath(packaged, destination.parent)).as_posix()
            if not rewritten.startswith("."):
                rewritten = "./" + rewritten
            return quote(rewritten, safe="/.-_~") + suffix

        documents[source] = rewrite_markdown_links(source.read_text() if contents is None else contents, rewrite)

    collect(source_document, source_text)
    for source, destination in sorted(destinations.items()):
        destination = safe_destination(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source in documents:
            destination.write_text(documents[source])
        else:
            shutil.copy2(source, destination)
    return [destinations[source] for source in documents]


def validate_review_bundle(output_dir, documents):
    output_dir = Path(output_dir).resolve()
    count = 0
    for document in documents:
        document = Path(document).resolve()
        if not document.is_relative_to(output_dir) or not document.is_file():
            raise ValueError(f"Missing/out-of-bundle review document: {document}")

        def check(link):
            nonlocal count
            local = local_link(link)
            if local:
                target = (document.parent / local[0]).resolve()
                if not target.is_relative_to(output_dir) or not target.is_file():
                    raise ValueError(f"Review bundle link is not self-contained: {document}: {link}")
                count += 1
            return link

        rewrite_markdown_links(document.read_text(), check)
    return count


def main():
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

    review_documents = []
    playtest_path = root / f"docs/week{week}_playtest.md"
    if week == 5:
        playtest = playtest_path.read_text().replace("[第五周评审追加记录](../11_week5_review.md#2026-10-08脸部反馈修订)",
                                                   "[本包构建信息](../11_week5_review.md#2026-10-08脸部反馈修订)")
        review_documents = collect_review_bundle(root, playtest_path, out, source_text=playtest,
                                                 redirects={root / "11_week5_review.md": out / "build_info.json"})
    else:
        shutil.copy2(playtest_path, out / "PLAYTEST.md")

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
        # These convenience launchers use the local pinned engine, not a Mac app.
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
            links = validate_review_bundle(out, review_documents)
            print(f"PLAYTEST_LINKS_PASS documents={len(review_documents)} local_links={links}")
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


if __name__ == "__main__":
    main()
