#!/usr/bin/env python3
"""Isolated Combat V1 review package; never changes source settings or PNGs.

--preflight-only is strictly read-only and fails on missing deliverables. The
optional JSON test plan may change a required gate's script/PASS regex, but
cannot omit a gate. Tests run against the same exported PCK with no source
overlay. macOS launchers require the local pinned Godot, not a standalone app.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import build_week5_candidate as art

VERSION = "0.6.0-week6-prototype"
SAVE_DIRECTORY = "ProjectWumingCombatV1Prototype"
BINARY = "ProjectWumingWeek6"
MAIN = "res://game/presentation/main.tscn"
TRIAL = "res://game/presentation/battle/combat_v1_trial.tscn"
SEED_IDS = ("SK_TRIP_WRIST", "SK_YUE_THRUST", "SK_YUE_GUARD", "SK_YUE_CROSSCUT", "SK_WATER_STEP", "IN_BREATH_BASIC")
NEW_RUNTIME_FILES = (
    "game/domain/battle/martial_loadout.gd", "game/domain/battle/battle_ai_profiles.gd",
    "game/presentation/battle/martial_preparation_panel.gd",
    "game/presentation/battle/combat_v1_trial.gd", TRIAL.removeprefix("res://"),
    "game/content/data/battle_skills.json", "game/content/data/battle_ai_profiles.json",
    "game/content/data/enemy_archetypes.json", "game/content/data/week6_ai_test_encounter.json",
    "game/content/data/combat_v1_trial.json",
)


def gate(identifier, script, marker):
    return {"id": identifier, "script": "game/tests/"+script, "marker": marker}


DEFAULT_TESTS = (
    gate("martial", "test_martial_loadout.gd", r"^MARTIAL_LOADOUT_PASS checks=[1-9]\d* packed=true\s*$"),
    gate("ai", "test_week6_ai.gd", r"^WEEK6_AI_PASS packed=true checks=[1-9]\d*\s*$"),
    gate("preview", "test_week6_battle_preview.gd", r"^WEEK6_BATTLE_PREVIEW_PASS checks=[1-9]\d* packed=true captures=0\s*$"),
    gate("preparation", "test_week6_preparation.gd", r"^WEEK6_PREPARATION_PASS\b[^\n]*\bpacked=true\b[^\n]*$"),
    gate("session", "test_week6_martial_session.gd", r"^WEEK6_MARTIAL_SESSION_PASS\b[^\n]*\bpacked=true\b[^\n]*$"),
    gate("trial", "test_week6_trial.gd", r"^WEEK6_TRIAL_PASS packed=true captures=0 checks=[1-9]\d*\s*$"),
    gate("story", "test_story_encounter.gd", r"^STORY_ENCOUNTER: [1-9]\d* checks, 0 failures[^\n]*$"),
    gate("onboarding", "test_onboarding.gd", r"^ONBOARDING: [1-9]\d* checks, 0 failures[^\n]*$"),
    gate("feedback", "test_week4_feedback.gd", r"^WEEK4_FEEDBACK: [1-9]\d* checks, 0 failures[^\n]*$"),
    gate("character", "test_character_imagegen_pipeline.gd", r"^CHARACTER_IMAGEGEN_PIPELINE_PASS checks=[1-9]\d* packed=true captures=0\s*$"),
)
REQUIRED_GATES = frozenset(entry["id"] for entry in DEFAULT_TESTS)
PREVIEW_NAMES = tuple("week6_preview_"+name+".png" for name in (
    "story_locked", "story_qi_blocked", "attack_confirm", "breath_capped", "guard_confirm", "story_cooldown",
    "step_confirm", "no_internal", "status_expiry", "registered_range", "support_confirm", "survive_goal"))
TRIAL_NAMES = tuple("week6_trial_"+name+".png" for name in ("selection", "preparation", "eliminate", "protection", "result"))
PREPARATION_NAMES = tuple(name+".png" for name in ("prep_default", "prep_changed", "prep_no_internal"))
CAPTURE_PLANS = (
    {"id": "character", "args": ["--capture-imagegen"], "files": art.EXPECTED_CAPTURES,
     "marker": r"^CHARACTER_IMAGEGEN_PIPELINE_PASS checks=[1-9]\d* packed=true captures=14\s*$"},
    {"id": "preview", "args": ["--capture-week6-preview"], "files": PREVIEW_NAMES,
     "marker": r"^WEEK6_BATTLE_PREVIEW_PASS checks=[1-9]\d* packed=true captures=12\s*$"},
    {"id": "preparation", "args": ["--capture-week6-preparation"], "files": PREPARATION_NAMES,
     "marker": r"^WEEK6_PREPARATION_PASS\b[^\n]*\bpacked=true\b[^\n]*\bcaptures=3\b[^\n]*$"},
    {"id": "trial", "args": ["--capture-week6-trial"], "files": TRIAL_NAMES,
     "marker": r"^WEEK6_TRIAL_PASS packed=true captures=5 checks=[1-9]\d*\s*$"},
)


def read_json(path):
    def reject(value):
        raise ValueError("Non-finite JSON number: "+value)
    return json.loads(Path(path).read_text(encoding="utf-8"), parse_constant=reject)


def test_plan(path=None):
    value = list(DEFAULT_TESTS) if path is None else read_json(path)
    if not isinstance(value, list): raise ValueError("Test plan must be a JSON array")
    result = []
    seen = set()
    for record in value:
        if not isinstance(record, dict) or set(record) != {"id", "script", "marker"}:
            raise ValueError("Test gate requires id, script and marker only")
        identifier, script, marker = record["id"], record["script"], record["marker"]
        if not isinstance(identifier, str) or identifier not in REQUIRED_GATES or identifier in seen:
            raise ValueError("Unknown or duplicate required gate")
        if (not isinstance(script, str) or not script.startswith("game/tests/") or not script.endswith(".gd")
                or "\\" in script or any(part in ("", ".", "..") for part in script.split("/"))):
            raise ValueError("Test script must be a canonical game/tests .gd path")
        if not isinstance(marker, str) or not marker.startswith("^") or not marker.endswith("$"):
            raise ValueError("PASS regex must match a complete log line")
        re.compile(marker)
        seen.add(identifier)
        result.append(dict(record))
    if seen != REQUIRED_GATES: raise ValueError("Required gates missing: "+", ".join(sorted(REQUIRED_GATES-seen)))
    return result


def review_preflight(root, seed):
    """Walk the same review attachment graph without making temporary copies."""
    root = Path(root).resolve()
    visited = set()
    def visit(path):
        path = path.resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Missing/out-of-project review target: "+str(path))
        relative = path.relative_to(root)
        allowed = (relative.parts[0] == "docs" and path.suffix.lower() in art.review.REVIEW_EXTENSIONS)
        allowed |= relative.parts[0] == "tools" and path.suffix == ".gd"
        allowed |= relative.parts[:2] in (("assets", "source"), ("assets", "runtime")) and path.suffix in {".md", ".gd", ".png", ".json"}
        allowed |= len(relative.parts) == 1 and path.suffix == ".md"
        if not allowed or any(part.startswith(".") for part in relative.parts):
            raise ValueError("Not an allowed review attachment: "+str(relative))
        if path in visited: return
        visited.add(path)
        if path == root / "12_week6_review.md" or path.suffix != ".md": return
        def check_link(link):
            local = art.review.local_link(link)
            if local: visit(path.parent/local[0])
            return link
        art.review.rewrite_markdown_links(path.read_text(encoding="utf-8"), check_link)
    visit(Path(seed))
    return sorted(str(path.relative_to(root)) for path in visited)


def production_preflight(root, plan):
    root = Path(root).resolve()
    provenance = art.production_preflight(root)
    required = NEW_RUNTIME_FILES + ("12_week6_review.md", "docs/week6_playtest.md", "tools/audit_pack.gd",
                                  "tools/check_story_persistence.py", "tools/check_martial_persistence.py",
                                  "game/tests/test_week6_martial_persistence.gd", "tools/build_hero_imagegen_manifest.py")
    for relative in required + tuple(entry["script"] for entry in plan):
        path = (root/relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Week6 deliverable missing or escapes root: "+relative)
    for entry in plan:
        if "--require-pack" not in (root/entry["script"]).read_text(encoding="utf-8"):
            raise ValueError("Packed gate must explicitly support --require-pack: "+entry["script"])
    project = (root/"project.godot").read_text(encoding="utf-8")
    if len(re.findall(r'^run/main_scene="'+re.escape(MAIN)+r'"\s*$', project, re.M)) != 1:
        raise ValueError("Normal source main entry must be preserved")
    hero_script = (root/"game/presentation/characters/hero_visual.gd").read_text(encoding="utf-8")
    if not re.search(r"^const ACTIVE_DATA_PATH\s*:?=\s*IMAGEGEN_DATA_PATH\s*$", hero_script, re.M):
        raise ValueError("Shared default hero must remain the active imagegen manifest")
    skills = read_json(root/"game/content/data/battle_skills.json")
    if not isinstance(skills, list) or any(not isinstance(skill, dict) for skill in skills):
        raise ValueError("Skill definitions must be dictionaries in an array")
    identifiers = [skill.get("id") for skill in skills]
    if any(not isinstance(identifier, str) for identifier in identifiers) or len(set(identifiers)) != len(identifiers):
        raise ValueError("Skill identifiers must be unique strings")
    indexed = {skill["id"]: skill for skill in skills}
    for identifier in SEED_IDS:
        skill = indexed.get(identifier, {})
        if skill.get("category") not in ("外功", "身法", "内功") or skill.get("ultimate") is not False:
            raise ValueError("Missing independent V1 martial definition: "+identifier)
    archetypes = read_json(root/"game/content/data/enemy_archetypes.json")
    if not isinstance(archetypes, dict) or not {"EN_YAMEN_BLADE", "EN_YAMEN_BOW", "EN_YAMEN_CATCHER"} <= set(archetypes):
        raise ValueError("Three enemy archetype templates required")
    documents = review_preflight(root, root/"docs/week6_playtest.md")
    return {"active_character": provenance, "martial_ids": list(SEED_IDS), "enemy_ids": sorted(archetypes),
            "test_plan": plan, "review_files": documents,
            "runtime_source_sha256": {relative: art.sha256(root/relative) for relative in NEW_RUNTIME_FILES}}


def stage_project_text(contents):
    substitutions = {"config/version": VERSION, "config/custom_user_dir_name": SAVE_DIRECTORY, "run/main_scene": MAIN}
    for key, value in substitutions.items():
        pattern = re.compile(r"^"+re.escape(key)+r'=.*$', re.M)
        if len(pattern.findall(contents)) != 1: raise ValueError("Expected one source setting: "+key)
        contents = pattern.sub(key+"="+json.dumps(value), contents)
    return contents


def verify_log(path, marker):
    contents = Path(path).read_text(encoding="utf-8")
    if re.search(r"SCRIPT ERROR:|ERROR:|Parse Error:|CHECK_TIMEOUT", contents):
        raise ValueError("Engine/check errors in evidence: "+str(path))
    matches = list(re.finditer(marker, contents, re.M))
    if len(matches) != 1: raise ValueError("Unique complete PASS marker required: "+str(path))
    line = matches[0].group(0)
    positive = re.search(r"\bchecks=[1-9]\d*\b", line) or re.search(r"\b[1-9]\d* checks, 0 failures\b", line)
    if not positive:
        positive = re.search(r"^[A-Z0-9_]+: [1-9]\d* checks, 0 failures[^\n]*$", contents, re.M)
    if line.startswith("PACK_AUDIT_PASS "):
        positive = re.search(r"\bresources=[1-9]\d* required=[1-9]\d*\b", line)
    if not positive: raise ValueError("Positive check count and zero-failure evidence required: "+str(path))
    return line.strip()


def verify_captures(folder, expected):
    folder = Path(folder)
    actual = {path.relative_to(folder).as_posix() for path in folder.rglob("*.png")}
    if actual != set(expected):
        raise ValueError(f"Incomplete/extra capture evidence: missing={sorted(set(expected)-actual)} extra={sorted(actual-set(expected))}")
    for filename in expected:
        info = art.validator.read_png_info(folder/filename)
        if (info.width, info.height) != (640, 360): raise ValueError("Native 640x360 capture required: "+filename)


def pack_probe_source(provenance):
    resources = ["res://"+path for path in NEW_RUNTIME_FILES if path.endswith((".gd", ".tscn"))]
    data_files = ["res://"+path for path in NEW_RUNTIME_FILES if path.endswith(".json")]
    literal = lambda value: json.dumps(value, ensure_ascii=False)
    return '\n'.join([
        'extends SceneTree', 'func _initialize() -> void:', '\t_run.call_deferred()', 'func _run() -> void:', '\tvar failures: Array[String] = []', '\tvar checks := 1',
        '\tif not FileAccess.file_exists("res://project.binary") or FileAccess.file_exists("res://project.godot"): failures.append("PCK without source overlay required")',
        '\tfor pair: Array in '+literal([["application/config/version", VERSION], ["application/config/custom_user_dir_name", SAVE_DIRECTORY], ["application/run/main_scene", MAIN]])+':',
        '\t\tchecks += 1', '\t\tif ProjectSettings.get_setting(pair[0], "") != pair[1]: failures.append("Wrong package setting: "+pair[0])',
        '\tfor path: String in '+literal(resources)+':', '\t\tchecks += 1', '\t\tif not ResourceLoader.exists(path): failures.append("Missing V1 runtime resource: "+path)',
        '\tfor path: String in '+literal(data_files)+':', '\t\tchecks += 1', '\t\tif not FileAccess.file_exists(path): failures.append("Missing V1 data: "+path)', '\tchecks += 1',
        '\tvar file := FileAccess.open('+literal(art.MANIFEST_RESOURCE)+', FileAccess.READ)',
        '\tif file == null: failures.append("Active manifest unavailable")',
        '\telse:', '\t\tvar hash := HashingContext.new()', '\t\thash.start(HashingContext.HASH_SHA256)', '\t\thash.update(file.get_buffer(file.get_length()))',
        '\t\tchecks += 1', '\t\tif hash.finish().hex_encode() != '+literal(provenance["manifest_sha256"])+': failures.append("Packed active manifest byte identity differs")',
        '\tfor failure: String in failures: printerr("WEEK6_PACK_CONTRACT_FAIL ", failure)',
        '\tif failures.is_empty(): print("WEEK6_PACK_CONTRACT_PASS checks=%d packed=true" % checks)',
        '\tquit(0 if failures.is_empty() else 1)', ''])


def launcher_text(root, scene=""):
    suffix = " "+scene if scene else ""
    return '#!/bin/bash\nset -e\ncd "$(dirname "$0")"\nexec '+shlex.quote(str(root/"tools/godot.sh"))+f' --path "$PWD" --main-pack "$PWD/{BINARY}.pck"'+suffix+"\n"


def handoff_text(metadata):
    return f"""# 第六周 Combat V1 独立评审候选

版本 {VERSION}；源提交 `{metadata['commit']}`；构建时工作树 {'有未提交修改' if metadata['dirty'] else '干净'}。

- [普通剧情入口](./Play-on-Mac.command)：保留探索／调查主流程；探索中按 M 整备武学。
- [演武入口](./CombatV1-on-Mac.command)：两人对三类敌人，选择清场或保护同伴坚持完整三轮。
- [试玩意见表](./PLAYTEST.md)：填写实际体验，不把自动测试当作人工签字。
- [本包精确构建与验证信息](./build_info.json)：源文件／验证器／原PNG／manifest／PCK／EXE身份。

Mac 启动器依赖本机已安装的固定版本 Godot，不是独立 macOS 应用。Windows EXE 与同名 PCK 须在同一目录；已导出并检查 x86_64 PE，尚未 Windows 真机运行。

独立存档目录为 `{SAVE_DIRECTORY}`，不读写普通开发版或第五周候选的存档。演武不发剧情奖励、不推进时段；普通剧情仍只有胜利确认结算才写回。

已验证同一 PCK 的六项特色武学／被动内功、三类数据化敌人、技能预览、整备、状态／存档、真实键盘演武、旧剧情与引导、主角原PNG表现。`evidence/` 为本包 Mac 实际渲染的 14 张角色、12 张技能／状态、3 张整备和5张演武图；`validation/` 为包内日志及两个独立进程的故事／武学冷重启证据。

以上只证明自动工程验收。Windows／实体手柄、最终审美与人工试玩仍未验；不是 Steam 发布版本，也不声称完成后续章节或美术量产。

执行 `shasum -a 256 -c SHA256SUMS.txt` 可验证本包文件。仓库中的 `12_week6_review.md` 是持续更新的工程记录，PLAYTEST 的该链接映射至本包 metadata；本 HANDOFF 与包内日志才对应这个候选，不将后续仓库记录冒称为同源证据。
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--project-root", type=Path, default=TOOLS.parent)
    parser.add_argument("--test-plan", type=Path, help="JSON array; required gates cannot be omitted")
    arguments = parser.parse_args(argv)
    root = arguments.project_root.resolve()
    try:
        plan = test_plan(arguments.test_plan)
        ready = production_preflight(root, plan)
    except (OSError, ValueError, RuntimeError) as error:
        print("WEEK6_PREFLIGHT_FAIL "+str(error), file=sys.stderr)
        return 1
    if arguments.preflight_only:
        print("WEEK6_PREFLIGHT_PASS "+json.dumps(ready, ensure_ascii=False, sort_keys=True))
        return 0
    subprocess.run([sys.executable, str(root/"tools/build_hero_imagegen_manifest.py"), "--verify"], cwd=root, check=True)
    verifier_hashes = {entry["script"]: art.sha256(root/entry["script"]) for entry in plan}
    def verify_frozen_verifiers():
        if verifier_hashes != {entry["script"]: art.sha256(root/entry["script"]) for entry in plan}:
            raise ValueError("Source verifiers changed during build; evidence cannot be mixed across revisions")
    git = lambda *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    output = root/"builds/week6"/f"{VERSION}_{git('rev-parse', '--short', 'HEAD')}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
    output.mkdir(parents=True, exist_ok=False)
    validation = output/"validation"
    validation.mkdir()
    pack = output/f"{BINARY}.pck"
    logs = []
    evidence_markers = {}
    def checked(label, *args, capture_dir=None):
        environment = dict(os.environ)
        if capture_dir is not None: environment["WUXIA_CAPTURE_DIR"] = str(capture_dir)
        subprocess.run([sys.executable, str(root/"tools/run_checked.py"), label, str(root/"tools/godot.sh"), *map(str, args)], cwd=root, env=environment, check=True)
        logs.append(label)
        return root/"builds/qa"/(label+".log")
    documents = art.review.collect_review_bundle(root, root/"docs/week6_playtest.md", output,
                                                 redirects={root/"12_week6_review.md": output/"build_info.json"})
    with tempfile.TemporaryDirectory(prefix="week6-v1-stage-", dir=root/"builds") as temporary:
        stage = Path(temporary)
        shutil.copytree(root/"game", stage/"game", ignore=shutil.ignore_patterns("tests", "tools"))
        shutil.copytree(root/"assets/runtime", stage/"assets/runtime")
        shutil.copy2(root/"export_presets.cfg", stage/"export_presets.cfg")
        (stage/"project.godot").write_text(stage_project_text((root/"project.godot").read_text(encoding="utf-8")), encoding="utf-8")
        art.verify_stage_images(stage, ready["active_character"], root/"docs/art_reference")
        for relative, expected in ready["runtime_source_sha256"].items():
            if art.sha256(stage/relative) != expected: raise ValueError("Runtime changed between preflight and staging: "+relative)
        staged_digest = art.stage_source_digest(stage)
        checked("week6_candidate_import", "--headless", "--path", stage, "--editor", "--import")
        art.verify_stage_images(stage, ready["active_character"], root/"docs/art_reference")
        checked("week6_candidate_export", "--headless", "--path", stage, "--export-release", "Windows Release", output/f"{BINARY}.exe")
        log = checked("week6_candidate_audit", "--headless", "--path", output, "--main-pack", pack, "--script", root/"tools/audit_pack.gd")
        verify_log(log, r"^PACK_AUDIT_PASS resources=[1-9]\d* required=[1-9]\d*\s*$")
        probe = validation/"week6_pack_contract.gd"
        probe.write_text(pack_probe_source(ready["active_character"]), encoding="utf-8")
        log = checked("week6_candidate_contract", "--headless", "--path", output, "--main-pack", pack, "--script", probe)
        verify_log(log, r"^WEEK6_PACK_CONTRACT_PASS checks=[1-9]\d* packed=true\s*$")
        for entry in plan:
            verify_frozen_verifiers()
            log = checked("week6_candidate_"+entry["id"], "--headless", "--path", output, "--main-pack", pack,
                          "--script", root/entry["script"], "--", "--require-pack")
            evidence_markers[entry["id"]] = verify_log(log, entry["marker"])
        indexed = {entry["id"]: entry for entry in plan}
        for capture in CAPTURE_PLANS:
            verify_frozen_verifiers()
            identifier = capture["id"]
            folder = output/"evidence"/identifier
            folder.mkdir(parents=True, exist_ok=False)
            args = list(capture["args"])+["--require-pack"]
            if identifier == "preparation": args.append("--capture-dir="+str(folder))
            log = checked("week6_candidate_render_"+identifier, "--path", output, "--main-pack", pack,
                          "--script", root/indexed[identifier]["script"], "--", *args, capture_dir=folder)
            evidence_markers["render_"+identifier] = verify_log(log, capture["marker"])
            verify_captures(folder, capture["files"])
        persistence = subprocess.run([sys.executable, str(root/"tools/check_story_persistence.py"), "--pack", str(pack)], cwd=root, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (validation/"persistence_restart.log").write_text(persistence.stdout, encoding="utf-8")
        print(persistence.stdout, end="")
        if "STORY_PERSISTENCE_RESTART_PASS" not in persistence.stdout: raise ValueError("Actual two-process persistence restart proof missing")
        logs += ["week4_pack_story_persistence_write", "week4_pack_story_persistence_read"]
        martial_persistence = subprocess.run([sys.executable, str(root/"tools/check_martial_persistence.py"), "--pack", str(pack)], cwd=root, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (validation/"martial_persistence_restart.log").write_text(martial_persistence.stdout, encoding="utf-8")
        print(martial_persistence.stdout, end="")
        if not re.search(r"^MARTIAL_PERSISTENCE_RESTART_PASS .* packed=true \(writer exited before reader launched\)$", martial_persistence.stdout, re.M):
            raise ValueError("Actual two-process martial persistence restart proof missing")
        logs += ["week6_pack_martial_persistence_write", "week6_pack_martial_persistence_read"]
        verify_frozen_verifiers()
        art.verify_pe(output/f"{BINARY}.exe")
        shutil.copytree(root/"licenses", output/"licenses")
        for filename, scene in (("Play-on-Mac.command", ""), ("CombatV1-on-Mac.command", TRIAL)):
            launcher = output/filename
            launcher.write_text(launcher_text(root, scene), encoding="utf-8")
            launcher.chmod(0o755)
        metadata = {"game_version": VERSION, "save_directory": SAVE_DIRECTORY,
                    "purpose": "local Combat V1 review; not Steam release", "main_scene": MAIN, "combat_v1_scene": TRIAL,
                    "commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
                    "engine": (root/".godot-version").read_text().strip(), "built_at_utc": datetime.now(timezone.utc).isoformat(),
                    "staged_source_sha256": staged_digest, "post_import_stage_sha256": art.stage_source_digest(stage), "source_verifiers_sha256": verifier_hashes,
                    "active_character": ready["active_character"], "runtime_source_sha256": ready["runtime_source_sha256"],
                    "martial_ids": ready["martial_ids"], "enemy_ids": ready["enemy_ids"], "test_plan": plan, "verified_markers": evidence_markers,
                    "pack_sha256": art.sha256(pack), "windows_exe_sha256": art.sha256(output/f"{BINARY}.exe"),
                    "validated_on": "same PCK macOS automated combat, preparation, story, active art and actual rendering; two-process persistence",
                    "not_verified": ["Windows hardware", "physical controller", "human playtest", "standalone macOS app"],
                    "capture_sets": {capture["id"]: list(capture["files"]) for capture in CAPTURE_PLANS}}
        (output/"build_info.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
        (output/"HANDOFF.md").write_text(handoff_text(metadata), encoding="utf-8")
        print(f"PLAYTEST_LINKS_PASS documents={len(documents)} local_links={art.review.validate_review_bundle(output, documents)}")
        for label in logs: shutil.copy2(root/"builds/qa"/(label+".log"), validation/(label+".log"))
        art.write_checksums(output)
    print("WEEK6_CANDIDATE_PASS "+str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
