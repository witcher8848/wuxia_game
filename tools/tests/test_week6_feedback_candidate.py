"""Protocol/unit fixtures only: never launch Godot or create a real candidate."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1]/"build_week6_feedback_candidate.py"
spec = importlib.util.spec_from_file_location("week6_feedback_candidate_tests",SCRIPT)
builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = builder
spec.loader.exec_module(builder)


class FeedbackCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="week6-feedback-unit-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)/"project"
        self.root.mkdir()
        self.plan = builder.test_plan()
        self.provenance = {"manifest_sha256":"a"*64,"raw_pngs":[]}

    def write(self,relative,contents="unit fixture\n"):
        path = self.root/relative
        path.parent.mkdir(parents=True,exist_ok=True)
        if isinstance(contents,bytes): path.write_bytes(contents)
        else: path.write_text(contents,encoding="utf-8")
        return path

    def fixture(self):
        for relative in builder.NEW_RUNTIME_FILES+builder.EXTRA_DELIVERABLES:
            self.write(relative,"{}" if relative.endswith(".json") else "fixture\n")
        for record in self.plan: self.write(record["script"],'# supports "--require-pack"\n')
        self.write("12_week6_review.md","Historical review\n")
        self.write(builder.USER_FEEDBACK,"用户原话：主角太高。\n- [ ] 满意（尚未人工确认）\n")
        self.write(builder.FOLLOWUP,'[原始反馈](./week6_playtest.md)\n工程状态，不代表满意。\n')
        self.write(builder.REVIEW_SEED,'[反馈落实](./week6_feedback_followup.md)\n- [ ] 人工验收\n')
        self.write("project.godot",'config/version="source"\nconfig/custom_user_dir_name="original"\nrun/main_scene="'+builder.MAIN+'"\n')
        self.write("game/presentation/characters/hero_visual.gd","const ACTIVE_DATA_PATH := IMAGEGEN_DATA_PATH\n")
        seed = [{"id":identifier,"category":"内功" if identifier.startswith("IN_") else "外功","ultimate":False} for identifier in builder.SEED_IDS]
        self.write("game/content/data/battle_skills.json",json.dumps(seed,ensure_ascii=False))
        self.write("game/content/data/enemy_archetypes.json",json.dumps({name:{} for name in ("EN_YAMEN_BLADE","EN_YAMEN_BOW","EN_YAMEN_CATCHER")}))
        tactical = [dict(row) for row in seed]+[{"id":"ACT_BREATH","effects":[]}]
        index = {row["id"]:row for row in tactical}
        index["SK_TRIP_WRIST"]["broken_mode"] = "next_hit"
        index["SK_YUE_THRUST"].update(qi_cost=2,cooldown_rounds=0,distance_bonus=3)
        index["SK_YUE_CROSSCUT"]["area_pattern"] = "front_arc"
        self.write(builder.TACTICS_TABLES["skills"],json.dumps(tactical,ensure_ascii=False))
        self.write(builder.TACTICS_TABLES["profiles"],json.dumps({name:{} for name in ("AI_PRESSURE","AI_RANGED","AI_CAPTURE")}))
        self.write(builder.TACTICS_TABLES["archetypes"],json.dumps({name:{"ai_profile":"AI_PRESSURE","skills":["SK_TRIP_WRIST"]} for name in ("EN_YAMEN_BLADE","EN_YAMEN_BOW","EN_YAMEN_CATCHER")}))
        self.write("game/presentation/battle/combat_v1_trial.gd",'\n'.join('const '+name+' := "res://'+builder.TACTICS_TABLES[key]+'"' for name,key in (("SKILLS_PATH","skills"),("ARCHETYPES_PATH","archetypes"),("PROFILES_PATH","profiles"))))
        self.write("game/core/services/content_db.gd",'var definitions = "res://'+builder.TACTICS_TABLES["skills"]+'"\n')
        self.write(".godot-version","4.7.2\n")

    def preflight(self):
        with mock.patch.object(builder.art,"production_preflight",return_value=self.provenance):
            return builder.production_preflight(self.root,self.plan)

    def marker(self,identifier,capture=False):
        records = builder.CAPTURE_PLANS if capture else self.plan
        return next(row["marker"] for row in records if row["id"] == identifier)

    def test_fifteen_required_gates_with_every_baseline_and_feedback(self):
        self.assertEqual(len(self.plan),15)
        self.assertEqual({row["id"] for row in self.plan},builder.REQUIRED_GATES)
        self.assertTrue({"martial","ai","preview","preparation","session","trial","story","onboarding","feedback","character","tactics","visibility","tactics_encounter","feedback_ui","feedback_session"} == builder.REQUIRED_GATES)

    def test_exact_six_capture_sets_and_49_native_images(self):
        self.assertEqual([len(row["files"]) for row in builder.CAPTURE_PLANS],[14,12,3,5,9,6])
        self.assertEqual(sum(len(row["files"]) for row in builder.CAPTURE_PLANS),49)
        self.assertIn("threat_overlay.png",builder.VISIBILITY_NAMES)
        self.assertEqual(builder.FEEDBACK_UI_NAMES,tuple("feedback_ui_"+name+".png" for name in ("overview","martial_list","multi_target","threat","tactics","status")))

    def test_old_builder_files_and_public_globals_unchanged(self):
        original_script = SCRIPT.parent/"build_week6_candidate.py"
        original = original_script.read_bytes()
        spec = importlib.util.spec_from_file_location("feedback_unit_unmodified_base",original_script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.VERSION,"0.6.0-week6-prototype")
        self.assertEqual(module.SAVE_DIRECTORY,"ProjectWumingCombatV1Prototype")
        self.assertEqual(len(module.DEFAULT_TESTS),10)
        self.assertEqual(len(module.CAPTURE_PLANS),4)
        self.assertEqual(original_script.read_bytes(),original)

    def test_cannot_drop_any_one_of_fifteen_gates(self):
        for omitted in self.plan:
            with self.subTest(omitted=omitted["id"]):
                path = self.write("plan.json",json.dumps([row for row in self.plan if row != omitted]))
                with self.assertRaisesRegex(ValueError,"gates missing"): builder.test_plan(path)

    def test_duplicate_unknown_unanchored_and_noncanonical_plans_rejected(self):
        invalid = [self.plan+[self.plan[0]]]
        for key,value in (("id","skip"),("script","../outside.gd"),("script","game/tests/../outside.gd"),("marker","PASS")):
            changed = [dict(row) for row in self.plan]
            changed[0][key] = value
            invalid.append(changed)
        for plan in invalid:
            with self.subTest(plan=plan[0]):
                with self.assertRaises(ValueError): builder.test_plan(self.write("plan.json",json.dumps(plan)))

    def test_all_five_new_gates_require_positive_unique_packed_pass(self):
        rows = {
            "tactics":"BATTLE_TACTICS_PASS checks=372 packed=true\n",
            "visibility":"BOARD_VISIBILITY_PASS checks=288 packed=true captures=0\n",
            "tactics_encounter":"TACTICS_ENCOUNTER_PASS checks=1234 packed=true configurations=4\n",
            "feedback_ui":"WEEK6_FEEDBACK_UI_PASS packed=true captures=0 checks=1234\n",
            "feedback_session":"WEEK6_FEEDBACK_SESSION_PASS checks=1234 packed=true\n",
        }
        for identifier,text in rows.items():
            marker = self.marker(identifier)
            builder.verify_log(self.write("gate.log",text),marker)
            for bad in (text+text,text.replace("packed=true","packed=false"),text.replace(re_check(text),"checks=0"),text+"TEST_FAIL broken\n",text+"CASE: 1 checks, 1 failures\n"):
                with self.subTest(identifier=identifier,bad=bad):
                    with self.assertRaises(ValueError): builder.verify_log(self.write("gate.log",bad),marker)

    def test_feedback_ui_capture_cannot_replace_headless_gate(self):
        text = "WEEK6_FEEDBACK_UI_PASS packed=true captures=6 checks=999\n"
        builder.verify_log(self.write("render.log",text),self.marker("feedback_ui",True))
        with self.assertRaises(ValueError): builder.verify_log(self.write("render.log",text),self.marker("feedback_ui"))

    def test_visibility_capture_requires_nine_not_eight_or_partial(self):
        text = "BOARD_VISIBILITY_PASS checks=999 packed=true captures=9\n"
        builder.verify_log(self.write("render.log",text),self.marker("visibility",True))
        for bad in (text.replace("captures=9","captures=8"),text.replace("checks=999","checks=0"),text+text):
            with self.assertRaises(ValueError): builder.verify_log(self.write("render.log",bad),self.marker("visibility",True))

    def test_tactics_encounter_requires_four_real_configurations(self):
        text = "TACTICS_ENCOUNTER_PASS checks=999 packed=true configurations=4\n"
        with self.assertRaises(ValueError): builder.verify_log(self.write("render.log",text.replace("configurations=4","configurations=2")),self.marker("tactics_encounter"))

    def test_preflight_reads_active_tactics_sha_and_full_inventory(self):
        self.fixture()
        before = {path.relative_to(self.root).as_posix():path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        ready = self.preflight()
        for key,path in builder.TACTICS_TABLES.items():
            self.assertEqual(ready["active_tactics"][key],{"path":"res://"+path,"sha256":builder.art.sha256(self.root/path)})
            self.assertIn(path,ready["runtime_source_sha256"])
            self.assertIn(path,ready["runtime_source_inventory"])
        self.assertEqual(ready["runtime_inventory_sha256"],builder.inventory_digest(ready["runtime_source_inventory"]))
        self.assertEqual(ready["user_feedback"]["sha256"],builder.art.sha256(self.root/builder.USER_FEEDBACK))
        self.assertNotIn("game/tests/test_board_visibility.gd",ready["runtime_source_inventory"])
        self.assertEqual(before,{path.relative_to(self.root).as_posix():path.read_bytes() for path in self.root.rglob("*") if path.is_file()})

    def test_missing_feedback_deliverables_fail_before_engine(self):
        self.fixture()
        (self.root/builder.REVIEW_SEED).unlink()
        with mock.patch.object(builder.subprocess,"run") as run,contextlib.redirect_stderr(io.StringIO()) as error:
            self.assertEqual(builder.main(["--project-root",str(self.root),"--preflight-only"]),1)
            run.assert_not_called()
        self.assertIn("WEEK6_FEEDBACK_PREFLIGHT_FAIL",error.getvalue())
        self.assertIn(builder.REVIEW_SEED,error.getvalue())
        self.assertFalse((self.root/"builds").exists())

    def test_new_tactics_table_is_required_not_legacy_padding(self):
        self.fixture()
        (self.root/builder.TACTICS_TABLES["skills"]).unlink()
        with self.assertRaisesRegex(ValueError,"battle_skills_tactics"): self.preflight()

    def test_missing_test_or_pack_guard_is_rejected(self):
        self.fixture()
        path = self.root/next(row["script"] for row in self.plan if row["id"] == "feedback_session")
        path.unlink()
        with self.assertRaisesRegex(ValueError,"feedback_session"): self.preflight()
        path.write_text("extends SceneTree\n")
        with self.assertRaisesRegex(ValueError,"require-pack"): self.preflight()

    def test_readonly_preflight_never_builds_or_commits_and_preserves_feedback(self):
        self.fixture()
        original = (self.root/builder.USER_FEEDBACK).read_bytes()
        with mock.patch.object(builder.art,"production_preflight",return_value=self.provenance),mock.patch.object(builder.subprocess,"run") as run,contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(builder.main(["--project-root",str(self.root),"--preflight-only"]),0)
            run.assert_not_called()
        self.assertIn("WEEK6_FEEDBACK_PREFLIGHT_PASS",output.getvalue())
        self.assertFalse((self.root/"builds").exists())
        self.assertEqual((self.root/builder.USER_FEEDBACK).read_bytes(),original)

    def test_followup_must_be_explicitly_linked(self):
        self.fixture()
        self.write(builder.REVIEW_SEED,"No follow-up link\n")
        with self.assertRaisesRegex(ValueError,"must link"): self.preflight()

    def test_runtime_binding_cannot_point_back_to_legacy_tables(self):
        self.fixture()
        path = self.root/"game/presentation/battle/combat_v1_trial.gd"
        path.write_text(path.read_text().replace("battle_skills_tactics.json","battle_skills.json"))
        with self.assertRaisesRegex(ValueError,"SKILLS_PATH"): self.preflight()

    def test_normal_preparation_requires_new_definition_binding(self):
        self.fixture()
        self.write("game/core/services/content_db.gd","var definitions = 'battle_skills.json'\n")
        with self.assertRaisesRegex(ValueError,"Normal martial"): self.preflight()

    def test_tactical_mechanics_cannot_be_old_single_target_or_guard_breath(self):
        for identifier,key,value in (("ACT_BREATH","effects",["guard"]),("SK_YUE_CROSSCUT","area_pattern","single"),("SK_TRIP_WRIST","broken_mode","legacy"),("SK_YUE_THRUST","cooldown_rounds",1)):
            self.fixture()
            path = self.root/builder.TACTICS_TABLES["skills"]
            rows = json.loads(path.read_text())
            next(row for row in rows if row["id"] == identifier)[key] = value
            path.write_text(json.dumps(rows))
            with self.subTest(identifier=identifier):
                with self.assertRaises(ValueError): self.preflight()

    def test_bad_numeric_tactics_are_structured_failures_not_type_errors(self):
        for value in (None,True,"3",1.5,0,-1,10**400):
            self.fixture()
            path = self.root/builder.TACTICS_TABLES["skills"]
            rows = json.loads(path.read_text())
            next(row for row in rows if row["id"] == "SK_YUE_THRUST")["distance_bonus"] = value
            path.write_text(json.dumps(rows))
            with self.subTest(value=value):
                with self.assertRaises(ValueError): self.preflight()

    def test_bad_ai_reference_shape_cannot_crash_preflight(self):
        self.fixture()
        path = self.root/builder.TACTICS_TABLES["archetypes"]
        values = json.loads(path.read_text())
        values["EN_YAMEN_BLADE"]["ai_profile"] = []
        path.write_text(json.dumps(values))
        with self.assertRaises(ValueError): self.preflight()

    def test_archive_snapshot_preserves_original_unchecked_review(self):
        self.fixture()
        before = (self.root/builder.USER_FEEDBACK).read_bytes()
        ready = self.preflight()
        self.assertEqual(ready["user_feedback"]["archive"],"USER_FEEDBACK_ORIGINAL.txt")
        self.assertIn("no acceptance",ready["user_feedback"]["policy"])
        self.assertEqual((self.root/builder.USER_FEEDBACK).read_bytes(),before)

    def test_runtime_inventory_excludes_tests_but_detects_extra_active_code(self):
        self.fixture()
        initial = builder.runtime_inventory(self.root)
        self.write("game/tests/other.gd","source-only")
        self.write("game/tools/other.gd","source-only")
        self.assertEqual(builder.runtime_inventory(self.root),initial)
        self.write("game/presentation/added_runtime.gd","actual runtime")
        current = builder.runtime_inventory(self.root)
        self.assertNotEqual(builder.inventory_digest(current),builder.inventory_digest(initial))

    def test_runtime_symlink_cannot_escape_project(self):
        self.fixture()
        outside = Path(self.temporary.name)/"outside"
        outside.mkdir()
        (self.root/"game/escape").symlink_to(outside,target_is_directory=True)
        with self.assertRaisesRegex(ValueError,"escapes project"): builder.runtime_inventory(self.root)

    def test_git_identity_preserves_worktree_prefix_and_truthful_dirty(self):
        with mock.patch.object(builder.subprocess,"check_output",side_effect=[" M docs/week6_playtest.md\n","a"*40+"\n"]) as call:
            identity = builder.git_identity(self.root)
        self.assertTrue(identity["dirty"])
        self.assertEqual(identity["status"]," M docs/week6_playtest.md")
        self.assertEqual([record.args[0][-2:] for record in call.call_args_list],[["status","--porcelain"],["rev-parse","HEAD"]])

    def test_git_identity_clean_is_not_forced_when_empty(self):
        with mock.patch.object(builder.subprocess,"check_output",side_effect=["","a"*40+"\n"]):
            self.assertFalse(builder.git_identity(self.root)["dirty"])

    def test_frozen_inputs_reject_runtime_review_and_git_changes(self):
        self.fixture()
        ready = self.preflight()
        identity = {"commit":"a"*40,"status":" M docs/week6_playtest.md","dirty":True}
        hashes = {builder.USER_FEEDBACK:builder.art.sha256(self.root/builder.USER_FEEDBACK)}
        verifiers = {self.plan[0]["script"]:builder.art.sha256(self.root/self.plan[0]["script"])}
        with mock.patch.object(builder,"git_identity",return_value=identity):
            builder.verify_frozen_sources(self.root,ready,verifiers,hashes,identity)
            self.write(builder.USER_FEEDBACK,"user changed feedback during build")
            with self.assertRaisesRegex(ValueError,"inputs changed"): builder.verify_frozen_sources(self.root,ready,verifiers,hashes,identity)
        self.fixture()
        ready = self.preflight()
        with mock.patch.object(builder,"git_identity",return_value={**identity,"dirty":False}):
            with self.assertRaisesRegex(ValueError,"dirty state"): builder.verify_frozen_sources(self.root,ready,verifiers,hashes,identity)

    def test_isolated_version_user_directory_and_same_pack_launchers(self):
        text = builder.stage_project_text('config/version="source"\nconfig/custom_user_dir_name="original"\nrun/main_scene="'+builder.MAIN+'"\n')
        self.assertIn(builder.VERSION,text)
        self.assertIn(builder.SAVE_DIRECTORY,text)
        self.assertNotEqual(builder.SAVE_DIRECTORY,"ProjectWumingCombatV1Prototype")
        for scene in ("",builder.TRIAL): self.assertIn(builder.BINARY+".pck",builder.launcher_text(self.root,scene))

    def test_packed_contract_hashes_new_tables_not_just_their_existence(self):
        self.fixture()
        ready = self.preflight()
        text = builder.pack_probe_source(ready)
        for row in ready["active_tactics"].values():
            self.assertIn(row["path"],text)
            self.assertIn(row["sha256"],text)
        for value in (builder.VERSION,builder.SAVE_DIRECTORY,"project.binary","project.godot","Packed active table byte identity differs","WEEK6_FEEDBACK_PACK_CONTRACT_PASS"):
            self.assertIn(value,text)

    def test_capture_files_must_be_exact_names_and_native_dimensions(self):
        folder = self.root/"images"
        folder.mkdir()
        for name in builder.FEEDBACK_UI_NAMES: (folder/name).write_bytes(b"unit fixture, not a real screenshot")
        with mock.patch.object(builder.art.validator,"read_png_info",return_value=SimpleNamespace(width=640,height=360)):
            builder.verify_captures(folder,builder.FEEDBACK_UI_NAMES)
            (folder/"extra.png").write_bytes(b"fixture")
            with self.assertRaisesRegex(ValueError,"extra"): builder.verify_captures(folder,builder.FEEDBACK_UI_NAMES)
            (folder/"extra.png").unlink()
        with mock.patch.object(builder.art.validator,"read_png_info",return_value=SimpleNamespace(width=1280,height=720)):
            with self.assertRaisesRegex(ValueError,"640x360"): builder.verify_captures(folder,builder.FEEDBACK_UI_NAMES)

    def story_restart(self):
        return "STORY_PERSISTENCE_WRITE: 136 checks, 0 failures fixture=user://tests/unit pid=100\nSTORY_PERSISTENCE_PHASE_EXITED phase=write returncode=0\nSTORY_PERSISTENCE_READ: 24 checks, 0 failures fixture=user://tests/unit pid=200\nSTORY_PERSISTENCE_PHASE_EXITED phase=read returncode=0\nSTORY_PERSISTENCE_RESTART_PASS fixture=user://tests/unit (writer exited before reader launched)\n"

    def martial_restart(self):
        return "MARTIAL_PERSISTENCE_PHASE_PASS phase=write pid=100 checks=16 packed=true fixture=user://tests/unit\nMARTIAL_PERSISTENCE_PHASE_EXITED phase=write pid=100 returncode=0\nMARTIAL_PERSISTENCE_PHASE_PASS phase=read pid=200 checks=25 packed=true fixture=user://tests/unit\nMARTIAL_PERSISTENCE_PHASE_EXITED phase=read pid=200 returncode=0\nMARTIAL_PERSISTENCE_RESTART_PASS fixture=user://tests/unit writer_pid=100 reader_pid=200 packed=true (writer exited before reader launched)\n"

    def test_two_existing_cold_restart_protocols_require_actual_complete_phases(self):
        for kind,text in (("story",self.story_restart()),("martial",self.martial_restart())):
            self.assertIn("RESTART_PASS",builder.verify_cold_restart(text,kind))
            for bad in (text+text,text.replace("pid=200","pid=100").replace("reader_pid=200","reader_pid=100"),text.replace("returncode=0","returncode=1",1),text+"PERSISTENCE_FAIL broken\n"):
                with self.subTest(kind=kind):
                    with self.assertRaises(ValueError): builder.verify_cold_restart(bad,kind)

    def test_cold_restart_summary_cannot_hide_nonpositive_or_wrong_fixture_phase(self):
        for bad in (self.martial_restart().replace("checks=16","checks=0"),self.martial_restart().replace("phase=read pid=200 checks=25 packed=true fixture=user://tests/unit","phase=read pid=200 checks=25 packed=true fixture=user://tests/other"),self.story_restart().replace("pid=200","pid=100")):
            with self.assertRaises(ValueError): builder.verify_cold_restart(bad,"story" if bad.startswith("STORY") else "martial")

    def test_new_feedback_session_phases_have_exact_packed_fixture_and_pid(self):
        text = "WEEK6_FEEDBACK_SESSION_PHASE_PASS phase=write pid=123 checks=20 packed=true fixture=user://tests/unit\n"
        self.assertEqual(builder.feedback_session_phase(text,"write","user://tests/unit"),"123")
        for bad in (text+text,text.replace("checks=20","checks=0"),text.replace("packed=true","packed=false"),text.replace("phase=write","phase=read"),text.replace("tests/unit","tests/other")):
            with self.assertRaises(ValueError): builder.feedback_session_phase(bad,"write","user://tests/unit")

    def test_handoff_separates_user_acceptance_and_platform_limits(self):
        text = builder.handoff_text({"commit":"a"*40,"dirty":True})
        for value in ("有未提交修改","未替你勾选满意","Windows真机","不是独立macOS","不是Steam","共49张","15项门禁",builder.SAVE_DIRECTORY,"USER_FEEDBACK_ORIGINAL.txt"):
            self.assertIn(value,text)


def re_check(text):
    import re
    return re.search(r"checks=\d+",text)[0]


if __name__ == "__main__":
    unittest.main()
