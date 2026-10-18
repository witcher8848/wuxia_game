#!/usr/bin/env python3
"""Build one isolated Week 8 VS0.1 candidate, never a Steam release.

Preflight is read-only. All engineering gates, native captures, and both cold
routes use the same PCK without source overlay. The optional test plan may only
reorder mandatory gates. Build execution includes native rendering; coordinate
it with other native tasks. Original character PNG/manifest bytes are unchanged.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import build_week6_candidate as b6

art = b6.art
VERSION = "0.8.0-week8-vs01"
SAVE_DIRECTORY = "ProjectWumingWeek8VS01"
BINARY = "ProjectWumingWeek8VS01"
MAIN = "res://game/presentation/main.tscn"
REVIEW_SEED = "docs/week8_playtest.md"
ENGINE_RELATIVE = ".tools/godot/Godot.app"
ENGINE_BINARY = "Contents/MacOS/Godot"
ENGINE_LICENSES = ("licenses/GODOT.txt", "licenses/GODOT-COPYRIGHT.txt")
RUNTIME_FILES = (
    "game/domain/investigation/branch_choice_rules.gd",
    "game/core/services/game_session.gd", "game/core/services/content_db.gd",
    "game/persistence/save_service.gd", "game/persistence/save_file_io.gd",
    "game/domain/world/world_rules.gd", "game/domain/investigation/story_encounter_rules.gd",
    "game/content/data/investigation.json", "game/content/dialogue/investigation.json",
    "game/presentation/main.gd", "game/presentation/investigation/branch_choice_panel.gd",
    "game/content/localization/investigation.csv",
)
EXTRA_DELIVERABLES = (
    REVIEW_SEED, "docs/week8_branch_design.md", "武侠RPG_第八周每日任务.md",
    "project.godot", "export_presets.cfg", ".godot-version",
    "tools/build_week8_candidate.py", "tools/build_week6_candidate.py",
    "tools/build_week5_candidate.py", "tools/build_week4_candidate.py",
    "tools/validate_hero_manifest.py", "tools/build_hero_imagegen_manifest.py",
    "tools/audit_pack.gd", "tools/run_checked.py", "tools/godot.sh",
) + ENGINE_LICENSES


def gate(identifier, script, marker):
    return {"id": identifier, "script": "game/tests/" + script, "marker": marker}


DEFAULT_TESTS = (
    gate("branch_rules", "test_branch_choice_rules.gd", r"^BRANCH_CHOICE_RULES: [1-9]\d* checks, 0 failures \(pure first-choice foundation only\)$"),
    gate("branch_session", "test_branch_choice_session.gd", r"^BRANCH_CHOICE_SESSION: [1-9]\d* checks, 0 failures; engineering foundation only$"),
    gate("anchors", "test_choice_anchors.gd", r"^CHOICE_ANCHORS_PASS checks=[1-9]\d*$"),
    gate("automatic", "test_automatic_saves.gd", r"^AUTOMATIC_SAVES_PASS checks=[1-9]\d*$"),
    gate("flow", "test_week8_flow.gd", r"^WEEK8_FLOW_PASS checks=[1-9]\d* failures=0 packed=true phase= choice=home pid=[1-9]\d* fixture=user://tests/week8_flow_[A-Za-z0-9_]+$"),
    gate("ui", "test_week8_branch_ui.gd", r"^WEEK8_BRANCH_UI_PASS checks=[1-9]\d* packed=true captures=0 \(keyboard UI; fixture travel; legal scripted combat; not human UX/time\)$"),
    gate("world", "test_week7_world_session.gd", r"^WEEK7_WORLD_SESSION_PASS checks=[1-9]\d* packed=true$"),
    gate("story", "test_story_encounter.gd", r"^STORY_ENCOUNTER: [1-9]\d* checks, 0 failures[^\n]*$"),
    gate("martial", "test_martial_loadout.gd", r"^MARTIAL_LOADOUT_PASS checks=[1-9]\d* packed=true$"),
    gate("character", "test_character_imagegen_pipeline.gd", r"^CHARACTER_IMAGEGEN_PIPELINE_PASS checks=[1-9]\d* packed=true captures=0$"),
)
REQUIRED_GATES = frozenset(record["id"] for record in DEFAULT_TESTS)
# This protocol is frozen together with test_week8_branch_ui.gd before building.
CAPTURE_NAMES = tuple(
    "week8_" + locale + "_" + choice + "_" + phase + ".png"
    for locale in ("zh_CN", "en") for choice in ("home", "dock")
    for phase in ("objective", "choice", "confirm", "battle", "aftermath", "grave_compare", "end", "routes")
) + ("week8_zh_CN_home_save_pending.png", "week8_zh_CN_home_progress_pending.png",
     "week8_zh_CN_home_world_pending.png", "week8_zh_CN_unsaved_title_retreat.png")
CAPTURE_CALLS = 37
CAPTURE_MARKER = rf"^WEEK8_BRANCH_UI_PASS checks=[1-9]\d* packed=true captures={CAPTURE_CALLS} \(keyboard UI; fixture travel; legal scripted combat; not human UX/time\)$"
ERROR_PATTERN = re.compile(
    r"SCRIPT ERROR:|ERROR:|Parse Error:|CHECK_TIMEOUT|Traceback \(most recent call last\):|"
    r"\b[1-9]\d* failures\b(?!\s*=)|\bfailures=[1-9]\d*\b|^[A-Z0-9_]*(?:_FAIL|_FAILED|_TIMEOUT)\b", re.M)


def read_json(path):
    def reject(value):
        raise ValueError("Non-finite JSON number: " + value)
    return json.loads(Path(path).read_text(encoding="utf-8"), parse_constant=reject)


def test_plan(path=None):
    value = [dict(record) for record in DEFAULT_TESTS] if path is None else read_json(path)
    expected = {record["id"]: record for record in DEFAULT_TESTS}
    if not isinstance(value, list):
        raise ValueError("Test plan must be an array")
    seen = set()
    for record in value:
        if not isinstance(record, dict) or set(record) != {"id", "script", "marker"}:
            raise ValueError("Test gate requires id, script and marker only")
        identifier = record["id"]
        if not isinstance(identifier, str) or identifier not in expected or identifier in seen:
            raise ValueError("Unknown or duplicate required gate")
        if record != expected[identifier]:
            raise ValueError("Mandatory gate script/marker cannot be weakened; only reordering is supported")
        seen.add(identifier)
    if seen != REQUIRED_GATES:
        raise ValueError("Required gates missing: " + ", ".join(sorted(REQUIRED_GATES - seen)))
    return [dict(record) for record in value]


def reject_failed_evidence(contents):
    if ERROR_PATTERN.search(contents):
        raise ValueError("Failed/error/timeout evidence cannot be accepted")


def verify_log(path, marker):
    contents = Path(path).read_text(encoding="utf-8")
    reject_failed_evidence(contents)
    found = list(re.finditer(marker, contents, re.M))
    if len(found) != 1:
        raise ValueError("Unique complete PASS marker required: " + str(path))
    line = found[0].group(0)
    if not (re.search(r"\bchecks=[1-9]\d*\b", line)
            or re.search(r"\b[1-9]\d* checks, 0 failures\b", line)
            or re.fullmatch(r"PACK_AUDIT_PASS resources=[1-9]\d* required=[1-9]\d*", line)):
        raise ValueError("Positive checks and zero-failure protocol required: " + str(path))
    return line


def runtime_inventory(root):
    root = Path(root).resolve()
    result = {}
    for folder in (root / "game", root / "assets/runtime"):
        for path in sorted(folder.rglob("*")):
            relative = path.relative_to(root)
            if relative.parts[:2] in (("game", "tests"), ("game", "tools")):
                continue
            if not path.resolve().is_relative_to(root):
                raise ValueError("Runtime input escapes project: " + str(relative))
            if path.is_file():
                result[relative.as_posix()] = art.sha256(path)
    result["export_presets.cfg"] = art.sha256(root / "export_presets.cfg")
    return result


def inventory_digest(inventory):
    digest = hashlib.sha256()
    for relative, value in sorted(inventory.items()):
        digest.update(relative.encode() + b"\0" + value.encode() + b"\0")
    return digest.hexdigest()


def engine_inventory(folder):
    folder = Path(folder).resolve()
    result = {}
    if not folder.is_dir():
        raise ValueError("Bundled official macOS Godot.app is required: " + str(folder))
    for path in sorted(folder.rglob("*")):
        if not path.resolve().is_relative_to(folder):
            raise ValueError("Runtime app symlink escapes its bundle: " + str(path))
        if path.is_file():
            result[path.relative_to(folder).as_posix()] = art.sha256(path)
    binary = folder / ENGINE_BINARY
    if ENGINE_BINARY not in result or not os.access(binary, os.X_OK):
        raise ValueError("Bundled Godot executable is missing or not executable")
    return result


def production_preflight(root, plan):
    root = Path(root).resolve()
    # Revalidate plans supplied directly by callers, not only CLI JSON input.
    if {record["id"] for record in plan} != REQUIRED_GATES or any(record not in DEFAULT_TESTS for record in plan) or len(plan) != len(DEFAULT_TESTS):
        raise ValueError("Every unchanged mandatory gate is required")
    for relative in RUNTIME_FILES + EXTRA_DELIVERABLES + tuple(record["script"] for record in plan):
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Week8 deliverable missing or escapes root: " + relative)
    source_project = (root / "project.godot").read_text(encoding="utf-8")
    if len(re.findall(r'^run/main_scene="' + re.escape(MAIN) + r'"$', source_project, re.M)) != 1:
        raise ValueError("Normal source main scene must be preserved")
    stage_project_text(source_project)
    hero = (root / "game/presentation/characters/hero_visual.gd").read_text(encoding="utf-8")
    if not re.search(r"^const ACTIVE_DATA_PATH\s*:?=\s*IMAGEGEN_DATA_PATH\s*$", hero, re.M):
        raise ValueError("Shared active imagegen hero must be retained")
    skills = read_json(root / "game/content/data/battle_skills_tactics.json")
    if not isinstance(skills, list) or any(not isinstance(row, dict) for row in skills):
        raise ValueError("Active martial definitions require an array of records")
    identifiers = [row.get("id") for row in skills]
    if any(not isinstance(identifier, str) for identifier in identifiers) or len(set(identifiers)) != len(identifiers):
        raise ValueError("Active martial identifiers must be unique strings")
    indexed = {row["id"]: row for row in skills}
    for identifier in b6.SEED_IDS:
        row = indexed.get(identifier, {})
        if row.get("category") not in ("外功", "身法", "内功") or row.get("ultimate") is not False:
            raise ValueError("Missing independent V1 martial definition: " + identifier)
    app = root / ENGINE_RELATIVE
    runtime = engine_inventory(app)
    for relative in ENGINE_LICENSES:
        if len((root / relative).read_bytes()) < 100:
            raise ValueError("Full existing Godot license text is required: " + relative)
    return {
        "active_character": art.production_preflight(root),
        "runtime_source_inventory": runtime_inventory(root),
        "engine_inventory": runtime,
        "engine_inventory_sha256": inventory_digest(runtime),
        "martial_ids": list(b6.SEED_IDS), "test_plan": plan,
        "review_files": b6.review_preflight(root, root / REVIEW_SEED),
    }


def stage_project_text(contents):
    for key, value in {"config/version": VERSION, "config/custom_user_dir_name": SAVE_DIRECTORY, "run/main_scene": MAIN}.items():
        pattern = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
        if len(pattern.findall(contents)) != 1:
            raise ValueError("Expected one source setting: " + key)
        contents = pattern.sub(key + "=" + json.dumps(value), contents)
    return contents


def git_identity(root):
    query = lambda *values: subprocess.check_output(["git", "-C", str(root), *values], text=True).rstrip("\n")
    status = query("status", "--porcelain")
    return {"commit": query("rev-parse", "HEAD"), "dirty": bool(status), "status": status}


def source_input_hashes(root, ready):
    """Freeze the complete review graph, not only the top-level feedback seed."""
    root = Path(root).resolve()
    relatives = set(EXTRA_DELIVERABLES) | set(ready["review_files"])
    for license_path in (root / "licenses").rglob("*"):
        if not license_path.resolve().is_relative_to(root / "licenses"):
            raise ValueError("License input escapes its directory")
        if license_path.is_file():
            relatives.add(license_path.relative_to(root).as_posix())
    result = {}
    for relative in sorted(relatives):
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Frozen source input missing or escapes root: " + relative)
        result[relative] = art.sha256(path)
    return result


def verify_frozen_sources(root, ready, verifier_hashes, input_hashes, identity):
    root = Path(root)
    if any(art.sha256(root / relative) != digest for relative, digest in {**verifier_hashes, **input_hashes}.items()):
        raise ValueError("Source verifier/document/tool changed during build")
    if runtime_inventory(root) != ready["runtime_source_inventory"] or git_identity(root) != identity:
        raise ValueError("Runtime source or Git dirty identity changed during build")
    if art.production_preflight(root) != ready["active_character"]:
        raise ValueError("Original production PNG/manifest identity changed during build")


def pack_probe_source(provenance):
    resources = ["res://" + relative for relative in RUNTIME_FILES if relative.endswith(".gd")]
    data = ["res://" + relative for relative in RUNTIME_FILES if relative.endswith(".json")]
    literal = lambda value: json.dumps(value, ensure_ascii=False)
    return "\n".join([
        "extends SceneTree", "func _initialize() -> void: _run.call_deferred()", "func _run() -> void:",
        "\tvar failures: Array[String] = []", "\tvar checks := 1",
        '\tif not FileAccess.file_exists("res://project.binary") or FileAccess.file_exists("res://project.godot"): failures.append("PCK without source overlay required")',
        "\tfor pair: Array in " + literal([["application/config/version", VERSION], ["application/config/custom_user_dir_name", SAVE_DIRECTORY], ["application/run/main_scene", MAIN]]) + ":",
        '\t\tchecks += 1', '\t\tif ProjectSettings.get_setting(pair[0], "") != pair[1]: failures.append("Wrong isolated setting")',
        "\tfor path: String in " + literal(resources) + ":", '\t\tchecks += 1', '\t\tif not ResourceLoader.exists(path): failures.append("Missing resource: " + path)',
        "\tfor path: String in " + literal(data) + ":", '\t\tchecks += 1', '\t\tif not FileAccess.file_exists(path): failures.append("Missing data: " + path)',
        '\tchecks += 1', '\tif FileAccess.get_sha256(' + literal(art.MANIFEST_RESOURCE) + ') != ' + literal(provenance["manifest_sha256"]) + ': failures.append("Manifest identity differs")',
        '\tfor failure: String in failures: printerr("WEEK8_PACK_CONTRACT_FAIL ", failure)',
        '\tif failures.is_empty(): print("WEEK8_PACK_CONTRACT_PASS checks=%d failures=0 packed=true" % checks)',
        '\tquit(0 if failures.is_empty() else 1)', "",
    ])


def launcher_text():
    # No repository path, user installation path, or project.godot dependency.
    return ('#!/bin/bash\nset -euo pipefail\ncd "$(dirname "$0")"\n'
            'task_engine="$PWD/runtime/Godot.app/' + ENGINE_BINARY + '"\n'
            'if [[ ! -x "$task_engine" ]]; then echo "Missing bundled Godot runtime; restore the complete candidate folder." >&2; exit 1; fi\n'
            'exec "$task_engine" --path "$PWD" --main-pack "$PWD/' + BINARY + '.pck" "$@"\n')


def portable_probe_source():
    return "\n".join([
        "extends SceneTree", "func _initialize() -> void: _run.call_deferred()", "func _run() -> void:",
        "\tvar failures: Array[String] = []", "\tvar checks := 5",
        '\tif DisplayServer.get_name() == "headless": failures.append("Native display required")',
        '\tif not FileAccess.file_exists("res://project.binary") or FileAccess.file_exists("res://project.godot"): failures.append("Only portable PCK required")',
        '\tif ProjectSettings.get_setting("application/config/version", "") != ' + json.dumps(VERSION) + ': failures.append("Wrong version")',
        '\tif ProjectSettings.get_setting("application/config/custom_user_dir_name", "") != ' + json.dumps(SAVE_DIRECTORY) + ': failures.append("Wrong save isolation")',
        '\tvar main: Node = load(' + json.dumps(MAIN) + ').instantiate()', '\troot.add_child(main)', '\tawait process_frame', '\tawait process_frame',
        '\tRenderingServer.force_draw(true)', '\tif main.get_node_or_null("UIRoot") == null or root.get_node("ContentDB").last_error != "": failures.append("Actual main/content startup failed")',
        '\troot.remove_child(main)', '\tmain.free()', '\tfor failure: String in failures: printerr("WEEK8_PORTABLE_LAUNCH_FAIL ", failure)',
        '\tif failures.is_empty(): print("WEEK8_PORTABLE_LAUNCH_PASS checks=%d failures=0 packed=true native=true" % checks)',
        '\tquit(0 if failures.is_empty() else 1)', "",
    ])


def cold_phase_pid(contents, phase, choice, fixture):
    reject_failed_evidence(contents)
    pattern = (rf"^WEEK8_FLOW_PASS checks=[1-9]\d* failures=0 packed=true phase={re.escape(phase)} "
               rf"choice={re.escape(choice)} pid=([1-9]\d*) fixture={re.escape(fixture)}$")
    matches = list(re.finditer(pattern, contents, re.M))
    if len(matches) != 1 or len(re.findall(r"^WEEK8_FLOW_PASS\b", contents, re.M)) != 1:
        raise ValueError("Missing/duplicate/mismatched cold phase proof")
    return int(matches[0][1])


def verify_cold_restart(contents, choice, fixture):
    reject_failed_evidence(contents)
    pids = []
    cursor = 0
    for phase in ("write", "read"):
        marker = re.compile(rf"^WEEK8_FLOW_PASS checks=[1-9]\d* failures=0 packed=true phase={phase} choice={re.escape(choice)} pid=([1-9]\d*) fixture={re.escape(fixture)}$", re.M)
        found = list(marker.finditer(contents))
        if len(found) != 1 or found[0].start() < cursor:
            raise ValueError("One ordered cold phase is required")
        pid = int(found[0][1])
        exit_marker = re.compile(rf"^WEEK8_FLOW_PHASE_EXITED phase={phase} choice={re.escape(choice)} pid={pid} returncode=0$", re.M)
        exited = list(exit_marker.finditer(contents))
        if len(exited) != 1 or exited[0].start() < found[0].end():
            raise ValueError("Actual successful process exit is required after each phase")
        cursor = exited[0].end()
        pids.append(pid)
    if pids[0] == pids[1] or len(re.findall(r"^WEEK8_FLOW_PASS\b", contents, re.M)) != 2:
        raise ValueError("Cold restart requires two distinct process identities")
    if len(re.findall(r"^WEEK8_FLOW_PHASE_EXITED\b", contents, re.M)) != 2:
        raise ValueError("Only the two exact successful phase exits may appear")
    return {"choice": choice, "fixture": fixture, "writer_pid": pids[0], "reader_pid": pids[1]}


def verify_captures(folder, expected=CAPTURE_NAMES):
    b6.verify_captures(folder, expected)


def packaged_playtest_text(source, metadata):
    summary = (f"状态：本包候选 {VERSION}，commit `{metadata['commit']}`，"
               f"dirty={str(metadata['dirty']).lower()}；工程证据见包内 HANDOFF.md 与 build_info.json。"
               "尚未邀请／收到本周5人反馈，当前0／5；约30分钟是待真人计时的目标，不是本包自动通行的测量结果。")
    source = re.sub(r"^状态：[^\n]*$", summary, source, count=1, flags=re.M)
    values = {
        "候选版本／构建目录": VERSION,
        "commit／dirty身份／PCK SHA": f"`{metadata['commit']}`／dirty={str(metadata['dirty']).lower()}／`{metadata['pack_sha256']}`",
        "启动方式、必要依赖": "双击 Play-on-Mac.command；保留包内 runtime/Godot.app。Windows EXE与PCK须同目录。",
        "存档目录／已知问题": SAVE_DIRECTORY + "；未完成后续章节／完整八阶段时限与六NPC事件。",
        "工程检查、Mac运行证据": "见本包 validation/ 与 evidence/；自动工程通行不计真人试玩。",
        "仓库外干净目录按测试者步骤启动": "本包已复制至仓库外目录，用相对启动器及内置运行时实际启动；见portable日志。",
        "Windows真实运行／实体手柄": "未验；Windows只导出并校验x86_64 PE，不推断真机运行。",
    }
    for key, value in values.items():
        source = re.sub(r"^\| " + re.escape(key) + r" \|[^\n]*$", "| " + key + " | " + value + " |", source, count=1, flags=re.M)
    return source


def handoff_text(metadata):
    return f"""# 第八周 VS0.1 内部候选

版本 `{VERSION}`；源提交 `{metadata['commit']}`；构建工作树{'有未提交修改（如实记录）' if metadata['dirty'] else '干净'}。

- [Mac试玩入口](./Play-on-Mac.command)：相对路径使用包内 `runtime/Godot.app`，整个目录可搬走，不依赖仓库或本机额外安装。
- Windows：运行 `{BINARY}.exe`，同名PCK必须保留。本包只验证Windows Release导出和x86_64 PE，未验Windows真机／实体手柄。
- [反馈表](./PLAYTEST.md)：当前0／5名真人反馈；约30分钟是待测目标，不把AI自动通行当真人计时或签字。
- [精确构建身份](./build_info.json)：源文件／验证器／dirty状态／原PNG及manifest／运行时／PCK／EXE的SHA。

存档独立目录 `{SAVE_DIRECTORY}`，不会读取开发版及旧候选存档。不可覆盖选择锚点与三槽自动存档分开。首次确认、战后取证、校勘、回顾与注册世界行动保存失败时，保留已确认运行时结果并提示重试，不重复结算。

`validation/` 包含同一PCK全部强制工程门与纸／人两路分别独立writer退出后的reader证据；`evidence/week8/` 是同PCK原生实际截图。另将包复制到仓库外系统临时目录，通过相对启动器和包内引擎原生加载实际主场景，日志为 `week8_portable_launch.log`。内置的是原官方Godot运行时，保留完整现有许可证；不是独立签名游戏App，不保证其他Mac可绕过系统安全提示。

这是内部灰盒，非Steam发布包；未完成完整三日八阶段、六核心NPC主动事件、最终结局或后续章节。未经邀请的真人反馈、自然通关时长、Windows真机、美术最终审美均保持未验。

执行 `shasum -a 256 -c SHA256SUMS.txt` 可验证包文件；外发／发布由你决定，本工具不会邀请测试者或推送。
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--project-root", type=Path, default=TOOLS.parent)
    parser.add_argument("--test-plan", type=Path, help="Mandatory records may be reordered, never omitted or weakened")
    arguments = parser.parse_args(argv)
    root = arguments.project_root.resolve()
    try:
        plan = test_plan(arguments.test_plan)
        ready = production_preflight(root, plan)
    except (OSError, ValueError, RuntimeError) as error:
        print("WEEK8_PREFLIGHT_FAIL " + str(error), file=sys.stderr)
        return 1
    if arguments.preflight_only:
        print("WEEK8_PREFLIGHT_PASS " + json.dumps(ready, ensure_ascii=False, sort_keys=True))
        return 0
    identity = git_identity(root)
    verifier_hashes = {record["script"]: art.sha256(root / record["script"]) for record in plan}
    input_hashes = source_input_hashes(root, ready)
    def frozen(): verify_frozen_sources(root, ready, verifier_hashes, input_hashes, identity)
    subprocess.run([sys.executable, str(root / "tools/build_hero_imagegen_manifest.py"), "--verify"], cwd=root, check=True)
    output = root / "builds/week8" / f"{VERSION}_{identity['commit'][:7]}_{datetime.now(timezone.utc):%Y%m%dT%H%M%S}_{time.time_ns()}"
    output.mkdir(parents=True, exist_ok=False)
    validation = output / "validation"
    validation.mkdir()
    pack = output / f"{BINARY}.pck"
    markers = {}
    restart_evidence = []
    engine = root / "tools/godot.sh"
    def checked(label, *args, capture_dir=None, command=None, cwd=None):
        frozen()
        environment = dict(os.environ)
        if command is None:
            # All source/export/PCK gates use the exact runtime copied below,
            # not an unrelated GODOT_BIN override from the developer shell.
            environment["GODOT_BIN"] = str(root / ENGINE_RELATIVE / ENGINE_BINARY)
        else:
            environment.pop("GODOT_BIN", None)
        if capture_dir is not None: environment["WUXIA_CAPTURE_DIR"] = str(capture_dir)
        subprocess.run([sys.executable, str(root / "tools/run_checked.py"), label,
                        str(engine) if command is None else str(command), *map(str, args)],
                       cwd=root if cwd is None else cwd, env=environment, check=True)
        log = validation / (label + ".log")
        shutil.copy2(root / "builds/qa" / (label + ".log"), log)
        return log
    with tempfile.TemporaryDirectory(prefix="week8-vs01-stage-", dir=root / "builds") as temporary:
        stage = Path(temporary)
        shutil.copytree(root / "game", stage / "game", ignore=shutil.ignore_patterns("tests", "tools"))
        shutil.copytree(root / "assets/runtime", stage / "assets/runtime")
        shutil.copy2(root / "export_presets.cfg", stage / "export_presets.cfg")
        (stage / "project.godot").write_text(stage_project_text((root / "project.godot").read_text(encoding="utf-8")), encoding="utf-8")
        if runtime_inventory(stage) != ready["runtime_source_inventory"]:
            raise ValueError("Staged runtime differs from preflight source bytes")
        art.verify_stage_images(stage, ready["active_character"], root / "docs/art_reference")
        source_digest = art.stage_source_digest(stage)
        checked("week8_candidate_import", "--headless", "--path", stage, "--editor", "--import")
        art.verify_stage_images(stage, ready["active_character"], root / "docs/art_reference")
        checked("week8_candidate_export", "--headless", "--path", stage, "--export-release", "Windows Release", output / f"{BINARY}.exe")
        art.verify_pe(output / f"{BINARY}.exe")
        log = checked("week8_candidate_audit", "--headless", "--path", output, "--main-pack", pack, "--script", root / "tools/audit_pack.gd")
        markers["pack_audit"] = verify_log(log, r"^PACK_AUDIT_PASS resources=[1-9]\d* required=[1-9]\d*$")
        probe = validation / "week8_pack_contract.gd"
        probe.write_text(pack_probe_source(ready["active_character"]), encoding="utf-8")
        log = checked("week8_candidate_contract", "--headless", "--path", output, "--main-pack", pack, "--script", probe)
        markers["pack_contract"] = verify_log(log, r"^WEEK8_PACK_CONTRACT_PASS checks=[1-9]\d* failures=0 packed=true$")
        copied_verifiers = {}
        for record in plan:
            copied = validation / "verifiers" / record["script"]
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / record["script"], copied)
            copied_verifiers[record["id"]] = copied
            if art.sha256(copied) != verifier_hashes[record["script"]]:
                raise ValueError("Verifier changed while copied")
            log = checked("week8_candidate_" + record["id"], "--headless", "--path", output, "--main-pack", pack,
                          "--script", copied, "--", "--require-pack")
            markers[record["id"]] = verify_log(log, record["marker"])
        for choice in ("home", "dock"):
            fixture = f"user://tests/week8_flow_candidate_{choice}_{os.getpid()}_{time.time_ns()}"
            combined = ""
            for phase in ("write", "read"):
                log = checked(f"week8_candidate_cold_{choice}_{phase}", "--headless", "--path", output, "--main-pack", pack,
                              "--script", copied_verifiers["flow"], "--", "--require-pack", "--phase=" + phase,
                              "--choice=" + choice, "--fixture=" + fixture)
                contents = log.read_text(encoding="utf-8")
                pid = cold_phase_pid(contents, phase, choice, fixture)
                combined += contents + f"\nWEEK8_FLOW_PHASE_EXITED phase={phase} choice={choice} pid={pid} returncode=0\n"
            restart_evidence.append(verify_cold_restart(combined, choice, fixture))
            (validation / f"week8_cold_{choice}_restart.log").write_text(combined, encoding="utf-8")
        folder = output / "evidence/week8"
        folder.mkdir(parents=True, exist_ok=False)
        log = checked("week8_candidate_render_ui", "--path", output, "--main-pack", pack, "--script", copied_verifiers["ui"],
                      "--", "--require-pack", "--capture-week8", capture_dir=folder)
        markers["render_ui"] = verify_log(log, CAPTURE_MARKER)
        verify_captures(folder)
        shutil.copytree(root / "licenses", output / "licenses")
        shutil.copytree(root / ENGINE_RELATIVE, output / "runtime/Godot.app", symlinks=True)
        if engine_inventory(output / "runtime/Godot.app") != ready["engine_inventory"]:
            raise ValueError("Copied runtime differs from the pinned local official bundle")
        binary = output / "runtime/Godot.app" / ENGINE_BINARY
        actual_version = subprocess.check_output([str(binary), "--version"], text=True).strip()
        pinned = (root / ".godot-version").read_text(encoding="utf-8").strip()
        if not actual_version.startswith(pinned + ".stable."):
            raise ValueError("Bundled runtime does not match the pinned stable Godot")
        launcher = output / "Play-on-Mac.command"
        launcher.write_text(launcher_text(), encoding="utf-8")
        launcher.chmod(0o755)
        portable_probe = validation / "week8_portable_launch.gd"
        portable_probe.write_text(portable_probe_source(), encoding="utf-8")
        # This is an actual external folder and launcher, not a repository cwd
        # plus --path that could accidentally depend on source or local tools.
        with tempfile.TemporaryDirectory(prefix="week8-portable-outside-") as external_name:
            external = Path(external_name).resolve()
            if external.is_relative_to(root):
                raise ValueError("Portable launch proof must be outside the source repository")
            shutil.copy2(pack, external / pack.name)
            if art.sha256(external / pack.name) != art.sha256(pack):
                raise ValueError("Portable copy is not the verified candidate PCK")
            shutil.copy2(launcher, external / launcher.name)
            shutil.copytree(output / "runtime", external / "runtime", symlinks=True)
            if engine_inventory(external / "runtime/Godot.app") != ready["engine_inventory"]:
                raise ValueError("Portable runtime is not byte-identical to the bundled runtime")
            shutil.copytree(output / "licenses", external / "licenses")
            external_probe = external / portable_probe.name
            shutil.copy2(portable_probe, external_probe)
            log = checked("week8_portable_launch", "--script", external_probe,
                          command=external / launcher.name, cwd=external)
            markers["portable_launch"] = verify_log(log, r"^WEEK8_PORTABLE_LAUNCH_PASS checks=[1-9]\d* failures=0 packed=true native=true$")
        frozen()
        metadata = {
            "game_version": VERSION, "save_directory": SAVE_DIRECTORY, "main_scene": MAIN,
            "purpose": "local Week 8 VS0.1 engineering candidate; not Steam release",
            "commit": identity["commit"], "dirty": identity["dirty"], "git_status_porcelain": identity["status"].splitlines(),
            "engine": actual_version, "built_at_utc": datetime.now(timezone.utc).isoformat(),
            "staged_source_sha256": source_digest, "post_import_stage_sha256": art.stage_source_digest(stage),
            "runtime_source_inventory": ready["runtime_source_inventory"], "runtime_inventory_sha256": inventory_digest(ready["runtime_source_inventory"]),
            "source_verifiers_sha256": verifier_hashes, "source_inputs_sha256": input_hashes,
            "active_character": ready["active_character"], "martial_ids": ready["martial_ids"],
            "bundled_engine_inventory": ready["engine_inventory"], "bundled_engine_inventory_sha256": ready["engine_inventory_sha256"],
            "pack_sha256": art.sha256(pack), "windows_exe_sha256": art.sha256(output / f"{BINARY}.exe"),
            "test_plan": plan, "verified_markers": markers, "cold_restarts": restart_evidence,
            "capture_files": list(CAPTURE_NAMES), "capture_calls": CAPTURE_CALLS,
            "portable_launch": {"outside_repository": True, "native": True, "bundled_engine": True, "log": "validation/week8_portable_launch.log"},
            "human_feedback": {"received": 0, "target": 5, "invited_by_builder": False}, "natural_playtime_minutes": None,
            "not_verified": ["30-minute first human playthrough", "five human feedback reports", "Windows hardware", "physical controller", "standalone signed game App", "other Macs"],
        }
        (output / "build_info.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        (output / "HANDOFF.md").write_text(handoff_text(metadata), encoding="utf-8")
        documents = art.review.collect_review_bundle(root, root / REVIEW_SEED, output,
                    source_text=packaged_playtest_text((root / REVIEW_SEED).read_text(encoding="utf-8"), metadata))
        links = art.review.validate_review_bundle(output, documents)
        print(f"PLAYTEST_LINKS_PASS documents={len(documents)} local_links={links}")
        frozen()
        art.write_checksums(output)
    print("WEEK8_CANDIDATE_PASS " + str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
