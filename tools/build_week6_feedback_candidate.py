#!/usr/bin/env python3
"""Build a separate, truthful week-six feedback review candidate.

No legacy builder/source settings/user review is changed. --preflight-only is
strictly read-only and fails on incomplete feedback deliverables. Required
baseline AND feedback gates run against the same PCK with no source overlay.
Dirty source is recorded, never committed merely to manufacture clean metadata.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("week6_feedback_private_base", TOOLS/"build_week6_candidate.py")
b6 = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = b6
spec.loader.exec_module(b6)
art = b6.art

VERSION = "0.6.1-week6-feedback"
SAVE_DIRECTORY = "ProjectWumingCombatFeedbackPrototype"
BINARY = "ProjectWumingWeek6Feedback"
MAIN = b6.MAIN
TRIAL = b6.TRIAL
SEED_IDS = b6.SEED_IDS
USER_FEEDBACK = "docs/week6_playtest.md"
REVIEW_SEED = "docs/week6_feedback_playtest.md"
FOLLOWUP = "docs/week6_feedback_followup.md"
TACTICS_TABLES = {
    "skills": "game/content/data/battle_skills_tactics.json",
    "profiles": "game/content/data/battle_ai_profiles_tactics.json",
    "archetypes": "game/content/data/enemy_archetypes_tactics.json",
}
ACTIVE_RUNTIME = (
    "game/core/services/content_db.gd", "game/core/services/game_session.gd",
    "game/domain/investigation/story_encounter_rules.gd",
    "game/domain/battle/battle_actions.gd", "game/domain/battle/battle_effects.gd",
    "game/domain/battle/battle_skills.gd", "game/domain/battle/combat_encounter.gd",
    "game/presentation/main.gd", "game/presentation/battle/battle_screen.gd",
    "game/presentation/battle/battle_board.gd", "game/presentation/battle/battle_text.gd",
    "game/presentation/battle/battle_skill_preview.gd", "game/presentation/battle/story_battle_screen.gd",
    "game/presentation/characters/hero_visual.gd",
)
NEW_RUNTIME_FILES = tuple(dict.fromkeys(b6.NEW_RUNTIME_FILES+ACTIVE_RUNTIME+tuple(TACTICS_TABLES.values())))
DEFAULT_TESTS = b6.DEFAULT_TESTS+(
    b6.gate("tactics", "test_battle_tactics.gd", r"^BATTLE_TACTICS_PASS checks=[1-9]\d* packed=true\s*$"),
    b6.gate("visibility", "test_board_visibility.gd", r"^BOARD_VISIBILITY_PASS checks=[1-9]\d* packed=true captures=0\s*$"),
    b6.gate("tactics_encounter", "test_tactics_encounter.gd", r"^TACTICS_ENCOUNTER_PASS checks=[1-9]\d* packed=true configurations=4\s*$"),
    b6.gate("feedback_ui", "test_week6_feedback_ui.gd", r"^WEEK6_FEEDBACK_UI_PASS packed=true captures=0 checks=[1-9]\d*\s*$"),
    b6.gate("feedback_session", "test_week6_feedback_session.gd", r"^WEEK6_FEEDBACK_SESSION_PASS checks=[1-9]\d* packed=true\s*$"),
)
REQUIRED_GATES = frozenset(record["id"] for record in DEFAULT_TESTS)
VISIBILITY_NAMES = tuple(name+".png" for name in (
    "battle_26px", "battle_28px", "adjacent_enemy", "adjacent_ally", "adjacent_obstacle",
    "move_preview", "move_confirmed", "attack_info_layer", "threat_overlay"))
FEEDBACK_UI_NAMES = tuple("feedback_ui_"+name+".png" for name in (
    "overview", "martial_list", "multi_target", "threat", "tactics", "status"))
CAPTURE_PLANS = b6.CAPTURE_PLANS+(
    {"id":"visibility", "args":["--capture-board-visibility"], "files":VISIBILITY_NAMES,
     "marker":r"^BOARD_VISIBILITY_PASS checks=[1-9]\d* packed=true captures=9\s*$"},
    {"id":"feedback_ui", "args":["--capture-week6-feedback-ui"], "files":FEEDBACK_UI_NAMES,
     "marker":r"^WEEK6_FEEDBACK_UI_PASS packed=true captures=6 checks=[1-9]\d*\s*$"},
)
EXTRA_DELIVERABLES = (
    FOLLOWUP, REVIEW_SEED, USER_FEEDBACK,
    "tools/check_story_persistence.py", "tools/check_martial_persistence.py",
    "game/tests/test_story_persistence.gd", "game/tests/test_week6_martial_persistence.gd",
    "tools/run_checked.py", "tools/audit_pack.gd", "tools/build_hero_imagegen_manifest.py",
    "tools/godot.sh", ".godot-version", "export_presets.cfg",
    "tools/build_week6_feedback_candidate.py", "tools/build_week6_candidate.py",
    "tools/build_week5_candidate.py", "tools/build_week4_candidate.py", "tools/validate_hero_manifest.py",
)

# Only this separately loaded module's globals are extended. The historical
# builder files/modules, their constants, and old candidates remain untouched.
for name in ("VERSION","SAVE_DIRECTORY","BINARY","NEW_RUNTIME_FILES","DEFAULT_TESTS","REQUIRED_GATES","CAPTURE_PLANS"):
    setattr(b6,name,globals()[name])
read_json = b6.read_json
test_plan = b6.test_plan
verify_captures = b6.verify_captures
stage_project_text = b6.stage_project_text
launcher_text = b6.launcher_text
review_preflight = b6.review_preflight


def reject_failed_evidence(contents):
    if re.search(r"SCRIPT ERROR:|ERROR:|Parse Error:|CHECK_TIMEOUT|Traceback \(most recent call last\):|\b[1-9]\d* failures\b|^[A-Z0-9_]*(?:_FAIL|_TIMEOUT)\b",contents,re.M):
        raise ValueError("Failed/error/timeout evidence cannot be accepted")


def verify_log(path,marker):
    reject_failed_evidence(Path(path).read_text(encoding="utf-8"))
    return b6.verify_log(path,marker)


def verify_cold_restart(contents,kind):
    """Reject partial/duplicate/nonpositive phases and require distinct PIDs."""
    reject_failed_evidence(contents)
    if kind == "martial":
        pattern = r"^MARTIAL_PERSISTENCE_PHASE_PASS phase=(write|read) pid=([1-9]\d*) checks=[1-9]\d* packed=true fixture=(\S+)\s*$"
        final = r"^MARTIAL_PERSISTENCE_RESTART_PASS fixture=(\S+) writer_pid=([1-9]\d*) reader_pid=([1-9]\d*) packed=true \(writer exited before reader launched\)\s*$"
    elif kind == "story":
        pattern = r"^STORY_PERSISTENCE_(WRITE|READ): [1-9]\d* checks, 0 failures fixture=(\S+) pid=([1-9]\d*)\s*$"
        final = r"^STORY_PERSISTENCE_RESTART_PASS fixture=(\S+) \(writer exited before reader launched\)\s*$"
    else: raise ValueError("Unknown cold-restart protocol")
    phases = list(re.finditer(pattern,contents,re.M))
    complete = list(re.finditer(final,contents,re.M))
    if len(phases) != 2 or len(complete) != 1 or phases[0][1].lower() != "write" or phases[1][1].lower() != "read":
        raise ValueError("Actual two-process "+kind+" cold-restart proof missing or duplicate")
    if kind == "story":
        fixtures = [phase[2] for phase in phases]
        pids = [phase[3] for phase in phases]
        exits = r"^STORY_PERSISTENCE_PHASE_EXITED phase=(write|read) returncode=0\s*$"
    else:
        fixtures = [phase[3] for phase in phases]
        pids = [phase[2] for phase in phases]
        exits = r"^MARTIAL_PERSISTENCE_PHASE_EXITED phase=(write|read) pid=([1-9]\d*) returncode=0\s*$"
        if (complete[0][2],complete[0][3]) != tuple(pids): raise ValueError("Restart summary PIDs differ from actual reported phases")
    finished = list(re.finditer(exits,contents,re.M))
    if len(finished) != 2 or finished[0][1] != "write" or finished[1][1] != "read" or not phases[0].end() <= finished[0].start() < phases[1].start() <= finished[1].start() < complete[0].start():
        raise ValueError("Writer must exit before the independent reader begins")
    if kind == "martial" and [item[2] for item in finished] != pids:
        raise ValueError("Exit evidence differs from actual reported phase PIDs")
    if len(set(pids)) != 2 or len(set(fixtures+[complete[0][1]])) != 1:
        raise ValueError("Cold restart requires different process identities and one exact fixture")
    return complete[0].group(0).strip()


def feedback_session_phase(contents,phase,fixture):
    reject_failed_evidence(contents)
    marker = rf"^WEEK6_FEEDBACK_SESSION_PHASE_PASS phase={phase} pid=([1-9]\d*) checks=[1-9]\d* packed=true fixture={re.escape(fixture)}\s*$"
    found = list(re.finditer(marker,contents,re.M))
    if len(found) != 1: raise ValueError("Missing/duplicate exact packed feedback-session "+phase+" proof")
    return found[0][1]


def runtime_inventory(root):
    """Every staged source/runtime input, excluding source-only tests/tools."""
    root = Path(root).resolve()
    result = {}
    for folder in (root/"game",root/"assets/runtime"):
        for path in sorted(folder.rglob("*")):
            if not path.resolve().is_relative_to(root): raise ValueError("Runtime input escapes project: "+str(path.relative_to(root)))
            if not path.is_file(): continue
            relative = path.relative_to(root)
            if relative.parts[:2] in (("game","tests"),("game","tools")): continue
            if not path.resolve().is_relative_to(root): raise ValueError("Runtime input escapes project: "+str(relative))
            result[relative.as_posix()] = art.sha256(path)
    result["export_presets.cfg"] = art.sha256(root/"export_presets.cfg")
    return result


def inventory_digest(inventory):
    digest = hashlib.sha256()
    for path,value in sorted(inventory.items()): digest.update(path.encode()+b"\0"+value.encode()+b"\0")
    return digest.hexdigest()


def git_identity(root):
    query = lambda *values: subprocess.check_output(["git","-C",str(root),*values],text=True).rstrip("\n")
    status = query("status","--porcelain")
    return {"commit":query("rev-parse","HEAD"),"status":status,"dirty":bool(status)}


def verify_frozen_sources(root,ready,verifier_hashes,input_hashes,identity):
    root = Path(root)
    if verifier_hashes != {path:art.sha256(root/path) for path in verifier_hashes}:
        raise ValueError("Feedback source verifiers changed during build")
    if input_hashes != {path:art.sha256(root/path) for path in input_hashes} or runtime_inventory(root) != ready["runtime_source_inventory"]:
        raise ValueError("Feedback runtime/doc/user inputs changed during build; mixed-source evidence rejected")
    if git_identity(root) != identity:
        raise ValueError("Git identity or dirty state changed during feedback build")


def validate_tactics(root):
    root = Path(root)
    skills = read_json(root/TACTICS_TABLES["skills"])
    if not isinstance(skills,list) or any(not isinstance(row,dict) for row in skills):
        raise ValueError("Tactics skills must be an array of records")
    identifiers = [row.get("id") for row in skills]
    if any(not isinstance(identifier,str) for identifier in identifiers) or len(set(identifiers)) != len(identifiers):
        raise ValueError("Tactics skill identifiers must be unique strings")
    indexed = {row["id"]:row for row in skills}
    for identifier in SEED_IDS:
        row = indexed.get(identifier,{})
        if row.get("category") not in ("外功","身法","内功") or row.get("ultimate") is not False:
            raise ValueError("Missing active tactics martial definition: "+identifier)
    if indexed.get("ACT_BREATH",{}).get("effects") != []:
        raise ValueError("Active feedback breath must restore without guard")
    thrust = indexed.get("SK_YUE_THRUST",{})
    whole = lambda value: type(value) in (int,float) and 0 <= value <= 32 and math.isfinite(value) and float(value).is_integer()
    if not all(whole(thrust.get(key)) for key in ("qi_cost","cooldown_rounds","distance_bonus")) or thrust.get("qi_cost") != 2 or thrust.get("cooldown_rounds") != 0 or not 0 < thrust.get("distance_bonus") <= 32:
        raise ValueError("Active feedback thrust must cost 2, have no cooldown, and reward distance")
    if indexed.get("SK_YUE_CROSSCUT",{}).get("area_pattern") != "front_arc":
        raise ValueError("Active feedback crosscut must have a real multi-target front arc")
    if indexed.get("SK_TRIP_WRIST",{}).get("broken_mode") != "next_hit":
        raise ValueError("Active feedback broken status must create a next-hit window")
    profiles = read_json(root/TACTICS_TABLES["profiles"])
    archetypes = read_json(root/TACTICS_TABLES["archetypes"])
    expected = {"EN_YAMEN_BLADE","EN_YAMEN_BOW","EN_YAMEN_CATCHER"}
    if not isinstance(profiles,dict) or not {"AI_PRESSURE","AI_RANGED","AI_CAPTURE"} <= set(profiles):
        raise ValueError("Active tactics AI profiles are incomplete")
    if not isinstance(archetypes,dict) or not expected <= set(archetypes):
        raise ValueError("Active tactics requires all three enemy templates")
    for identifier in expected:
        row = archetypes[identifier]
        if not isinstance(row,dict) or not isinstance(row.get("ai_profile"),str) or row.get("ai_profile") not in profiles or not isinstance(row.get("skills"),list):
            raise ValueError("Tactics enemy template has unresolved profile/skills: "+identifier)
        if any(not isinstance(skill,str) or skill not in indexed for skill in row["skills"]):
            raise ValueError("Tactics enemy references missing active skill: "+identifier)
    trial = (root/TRIAL.replace(".tscn",".gd").removeprefix("res://")).read_text(encoding="utf-8")
    for name,table in (("SKILLS_PATH","skills"),("ARCHETYPES_PATH","archetypes"),("PROFILES_PATH","profiles")):
        pattern = r'^const '+name+r'\s*:?=\s*"res://'+re.escape(TACTICS_TABLES[table])+r'"\s*$'
        if len(re.findall(pattern,trial,re.M)) != 1:
            raise ValueError("Production trial must explicitly bind active feedback "+name)
    content = (root/"game/core/services/content_db.gd").read_text(encoding="utf-8")
    if "res://"+TACTICS_TABLES["skills"] not in content:
        raise ValueError("Normal martial preparation is not bound to active tactics definitions")
    return {key:{"path":"res://"+path,"sha256":art.sha256(root/path)} for key,path in TACTICS_TABLES.items()}


def production_preflight(root,plan):
    root = Path(root).resolve()
    for relative in NEW_RUNTIME_FILES+EXTRA_DELIVERABLES+tuple(record["script"] for record in plan):
        path = (root/relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Feedback deliverable missing or escapes root: "+relative)
    ready = b6.production_preflight(root,plan)
    ready["active_tactics"] = validate_tactics(root)
    ready["review_files"] = review_preflight(root,root/REVIEW_SEED)
    ready["followup_files"] = review_preflight(root,root/FOLLOWUP)
    if FOLLOWUP not in ready["review_files"]:
        raise ValueError("Feedback playtest must link its feedback follow-up explicitly")
    ready["user_feedback"] = {"source":USER_FEEDBACK,"sha256":art.sha256(root/USER_FEEDBACK),
                              "archive":"USER_FEEDBACK_ORIGINAL.txt","policy":"exact original bytes; no acceptance inferred or checked"}
    ready["runtime_source_inventory"] = runtime_inventory(root)
    ready["runtime_inventory_sha256"] = inventory_digest(ready["runtime_source_inventory"])
    return ready


def pack_probe_source(ready):
    text = b6.pack_probe_source(ready["active_character"])
    rows = [["res://"+path,digest] for path,digest in ready["runtime_source_sha256"].items() if path.endswith(".json")]
    block = '\n'.join([
        '\tfor record: Array in '+json.dumps(rows,ensure_ascii=False)+':', '\t\tchecks += 1',
        '\t\tvar original := FileAccess.open(record[0],FileAccess.READ)',
        '\t\tif original == null:', '\t\t\tfailures.append("Required packed table unreadable: "+record[0])', '\t\t\tcontinue',
        '\t\tvar table_hash := HashingContext.new()', '\t\ttable_hash.start(HashingContext.HASH_SHA256)',
        '\t\ttable_hash.update(original.get_buffer(original.get_length()))',
        '\t\tif table_hash.finish().hex_encode() != record[1]: failures.append("Packed active table byte identity differs: "+record[0])',
    ])+'\n'
    if text.count('\tfor failure: String in failures:') != 1: raise ValueError("Shared pack-probe contract anchor changed")
    text = text.replace('\tfor failure: String in failures:',block+'\tfor failure: String in failures:')
    return text.replace("WEEK6_PACK_CONTRACT_","WEEK6_FEEDBACK_PACK_CONTRACT_")


def handoff_text(metadata):
    return f"""# 第六周反馈修订独立评审候选

版本 {VERSION}；源提交 `{metadata['commit']}`；构建工作树 {'有未提交修改（如实记录，未为制造clean而提交）' if metadata['dirty'] else '干净'}。

- [普通剧情入口](./Play-on-Mac.command)：探索中 M 查看全部已学武学并整备；已确认配装进入战斗时采用修订武学。
- [战斗反馈演武入口](./CombatFeedback-on-Mac.command)：清场／保护同伴两目标，试不同配装；演武不结算剧情奖励或时间。
- [新试玩意见表](./PLAYTEST.md)：重新填写真实体验，未替你勾选满意。
- [用户原反馈逐字节档案](./USER_FEEDBACK_ORIGINAL.txt)：原表原文不被新结果覆盖。
- [反馈落实说明](./review/docs/week6_feedback_followup.md)：工程处理情况不是人工验收签字。
- [本包精确身份](./build_info.json)：active tactics 三表、源快照、验证器、原图、PCK／EXE与dirty状态。

战斗角色约27px高，探索／角色实验室仍沿用原尺寸与原PNG；T红纹表示敌方现站位招式物理射程，忽略内力／冷却，移动后重算；紫框仍表示移动，不是锁定的未来攻击计划。承岳横截是真正多目标扫击，承岳直势重视射距与内力，吐纳不再同时获得守势。

已运行同一 PCK 的15项门禁及4场实际战术配置、故事／武学／新反馈配装各自两个独立进程冷重启；Mac 实际渲染为14角色＋12旧预览＋3整备＋5演武＋9遮挡／叠加＋6反馈界面，共49张640×360图。旧baseline表留作兼容证据，不冒称新战术表。

Mac启动器依赖本机固定Godot，不是独立macOS应用。Windows EXE已导出并检查x86_64 PE，但Windows真机／实体手柄／最终审美／人工博弈感尚未验，不是Steam发布版本。

独立存档目录 `{SAVE_DIRECTORY}` 不覆盖普通开发版／此前候选；原PNG／alpha不加工，所有截图只是视口证据。运行 `shasum -a 256 -c SHA256SUMS.txt` 验证本包。包内日志、metadata与本说明对应本候选；仓库中后续更新不被冒称为同源证据。
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only",action="store_true")
    parser.add_argument("--project-root",type=Path,default=TOOLS.parent)
    parser.add_argument("--test-plan",type=Path)
    args = parser.parse_args(argv)
    root = args.project_root.resolve()
    try:
        plan = test_plan(args.test_plan)
        ready = production_preflight(root,plan)
    except (OSError,ValueError,RuntimeError,re.error) as error:
        print("WEEK6_FEEDBACK_PREFLIGHT_FAIL "+str(error),file=sys.stderr)
        return 1
    if args.preflight_only:
        print("WEEK6_FEEDBACK_PREFLIGHT_PASS "+json.dumps(ready,ensure_ascii=False,sort_keys=True))
        return 0
    subprocess.run([sys.executable,str(root/"tools/build_hero_imagegen_manifest.py"),"--verify"],cwd=root,check=True)
    identity = git_identity(root)
    commit,status = identity["commit"],identity["status"]
    verifier_hashes = {record["script"]:art.sha256(root/record["script"]) for record in plan}
    inputs = set(NEW_RUNTIME_FILES+EXTRA_DELIVERABLES+tuple(verifier_hashes)+("project.godot",)+tuple(ready["review_files"])+tuple(ready["followup_files"]))
    inputs.update(path.relative_to(root).as_posix() for path in (root/"licenses").rglob("*") if path.is_file())
    input_hashes = {path:art.sha256(root/path) for path in sorted(inputs)}
    def frozen():
        verify_frozen_sources(root,ready,verifier_hashes,input_hashes,identity)
    output = root/"builds/week6_feedback"/f"{VERSION}_{commit[:7]}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
    output.mkdir(parents=True,exist_ok=False)
    validation = output/"validation"
    validation.mkdir()
    pack = output/(BINARY+".pck")
    logs = []
    markers = {}
    def checked(label,*values,capture_dir=None):
        environment = dict(os.environ)
        if capture_dir is not None: environment["WUXIA_CAPTURE_DIR"] = str(capture_dir)
        subprocess.run([sys.executable,str(root/"tools/run_checked.py"),label,str(root/"tools/godot.sh"),*map(str,values)],cwd=root,env=environment,check=True)
        logs.append(label)
        return root/"builds/qa"/(label+".log")
    documents = art.review.collect_review_bundle(root,root/REVIEW_SEED,output,
                                                redirects={root/"12_week6_review.md":output/"build_info.json"})
    shutil.copy2(root/USER_FEEDBACK,output/"USER_FEEDBACK_ORIGINAL.txt")
    with tempfile.TemporaryDirectory(prefix="week6-feedback-stage-",dir=root/"builds") as temporary:
        stage = Path(temporary)
        shutil.copytree(root/"game",stage/"game",ignore=shutil.ignore_patterns("tests","tools"))
        shutil.copytree(root/"assets/runtime",stage/"assets/runtime")
        shutil.copy2(root/"export_presets.cfg",stage/"export_presets.cfg")
        (stage/"project.godot").write_text(stage_project_text((root/"project.godot").read_text(encoding="utf-8")),encoding="utf-8")
        if runtime_inventory(stage) != ready["runtime_source_inventory"]: raise ValueError("Staged source differs from feedback preflight inputs")
        art.verify_stage_images(stage,ready["active_character"],root/"docs/art_reference")
        staged_digest = art.stage_source_digest(stage)
        frozen()
        checked("week6_feedback_candidate_import","--headless","--path",stage,"--editor","--import")
        art.verify_stage_images(stage,ready["active_character"],root/"docs/art_reference")
        if art.stage_source_digest(stage) != staged_digest: raise ValueError("Import modified staged feedback source inputs")
        checked("week6_feedback_candidate_export","--headless","--path",stage,"--export-release","Windows Release",output/(BINARY+".exe"))
        log = checked("week6_feedback_candidate_audit","--headless","--path",output,"--main-pack",pack,"--script",root/"tools/audit_pack.gd")
        verify_log(log,r"^PACK_AUDIT_PASS resources=[1-9]\d* required=[1-9]\d*\s*$")
        probe = validation/"week6_feedback_pack_contract.gd"
        probe.write_text(pack_probe_source(ready),encoding="utf-8")
        log = checked("week6_feedback_candidate_contract","--headless","--path",output,"--main-pack",pack,"--script",probe)
        verify_log(log,r"^WEEK6_FEEDBACK_PACK_CONTRACT_PASS checks=[1-9]\d* packed=true\s*$")
        for record in plan:
            frozen()
            log = checked("week6_feedback_candidate_"+record["id"],"--headless","--path",output,"--main-pack",pack,"--script",root/record["script"],"--","--require-pack")
            markers[record["id"]] = verify_log(log,record["marker"])
        indexed = {record["id"]:record for record in plan}
        for capture in CAPTURE_PLANS:
            frozen()
            identifier = capture["id"]
            folder = output/"evidence"/identifier
            folder.mkdir(parents=True,exist_ok=False)
            values = list(capture["args"])+["--require-pack"]
            if identifier == "preparation": values.append("--capture-dir="+str(folder))
            log = checked("week6_feedback_candidate_render_"+identifier,"--path",output,"--main-pack",pack,"--script",root/indexed[identifier]["script"],"--",*values,capture_dir=folder)
            markers["render_"+identifier] = verify_log(log,capture["marker"])
            verify_captures(folder,capture["files"])
        for kind,script,phase_logs in (
            ("story","check_story_persistence.py",["week4_pack_story_persistence_write","week4_pack_story_persistence_read"]),
            ("martial","check_martial_persistence.py",["week6_pack_martial_persistence_write","week6_pack_martial_persistence_read"]),
        ):
            frozen()
            result = subprocess.run([sys.executable,str(root/"tools"/script),"--pack",str(pack)],cwd=root,check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            (validation/(kind+"_persistence_restart.log")).write_text(result.stdout,encoding="utf-8")
            print(result.stdout,end="")
            verify_cold_restart(result.stdout,kind)
            logs += phase_logs
        # A third cold restart proves the NEW production M->tactics/session
        # path, not merely compatibility of the historical baseline saves.
        fixture = f"user://tests/feedback_session_{os.getpid()}_{time.time_ns()}"
        phase_pids = []
        restart_parts = []
        for phase in ("write","read"):
            frozen()
            log = checked("week6_feedback_session_persistence_"+phase,"--headless","--path",output,"--main-pack",pack,
                          "--script",root/indexed["feedback_session"]["script"],"--","--require-pack","--fixture="+fixture,"--phase="+phase)
            contents = log.read_text(encoding="utf-8")
            pid = feedback_session_phase(contents,phase,fixture)
            phase_pids.append(pid)
            restart_parts.extend([contents,f"WEEK6_FEEDBACK_SESSION_PHASE_EXITED phase={phase} pid={pid} returncode=0\n"])
        if len(set(phase_pids)) != 2: raise ValueError("New feedback-session cold reader reused writer PID")
        proof = f"WEEK6_FEEDBACK_SESSION_RESTART_PASS fixture={fixture} writer_pid={phase_pids[0]} reader_pid={phase_pids[1]} packed=true (writer exited before reader launched)\n"
        restart_parts.append(proof)
        (validation/"feedback_session_persistence_restart.log").write_text("".join(restart_parts),encoding="utf-8")
        print(proof,end="")
        frozen()
        art.verify_pe(output/(BINARY+".exe"))
        shutil.copytree(root/"licenses",output/"licenses")
        for name,scene in (("Play-on-Mac.command",""),("CombatFeedback-on-Mac.command",TRIAL)):
            launcher = output/name
            launcher.write_text(launcher_text(root,scene),encoding="utf-8")
            launcher.chmod(0o755)
        metadata = {
            "game_version":VERSION,"save_directory":SAVE_DIRECTORY,"purpose":"local week-six feedback review; not Steam release",
            "main_scene":MAIN,"combat_v1_scene":TRIAL,"commit":commit,"dirty":bool(status),"git_status_porcelain":status.splitlines(),
            "engine":(root/".godot-version").read_text().strip(),"built_at_utc":datetime.now(timezone.utc).isoformat(),
            "staged_source_sha256":staged_digest,"post_import_stage_sha256":art.stage_source_digest(stage),
            "source_input_sha256":input_hashes,"source_verifiers_sha256":verifier_hashes,
            "runtime_source_inventory":ready["runtime_source_inventory"],"runtime_inventory_sha256":ready["runtime_inventory_sha256"],
            "runtime_source_sha256":ready["runtime_source_sha256"],"active_character":ready["active_character"],"active_tactics":ready["active_tactics"],
            "user_feedback":ready["user_feedback"],"martial_ids":ready["martial_ids"],"enemy_ids":ready["enemy_ids"],
            "test_plan":plan,"verified_markers":markers,"pack_sha256":art.sha256(pack),"windows_exe_sha256":art.sha256(output/(BINARY+".exe")),
            "validated_on":"same PCK macOS automated feedback/baseline combat, preparation, tactics, active-art rendering; two-process persistence",
            "not_verified":["Windows hardware","physical controller","human tactical acceptance","final aesthetics","standalone macOS app"],
            "capture_sets":{record["id"]:list(record["files"]) for record in CAPTURE_PLANS},
            "cold_restart_protocols":["story","martial","feedback_session"],
        }
        (output/"build_info.json").write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
        (output/"HANDOFF.md").write_text(handoff_text(metadata),encoding="utf-8")
        print("PLAYTEST_LINKS_PASS documents=%d local_links=%d" % (len(documents),art.review.validate_review_bundle(output,documents)))
        for label in logs: shutil.copy2(root/"builds/qa"/(label+".log"),validation/(label+".log"))
        if art.sha256(output/"USER_FEEDBACK_ORIGINAL.txt") != ready["user_feedback"]["sha256"]: raise ValueError("User feedback archive differs from exact original bytes")
        art.write_checksums(output)
    print("WEEK6_FEEDBACK_CANDIDATE_PASS "+str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
