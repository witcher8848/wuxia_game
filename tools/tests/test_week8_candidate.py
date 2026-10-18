"""Read-only packaging/protocol tests; never import/export or launch Godot."""
import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "build_week8_candidate.py"
spec = importlib.util.spec_from_file_location("week8_candidate_tests", SCRIPT)
builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = builder
spec.loader.exec_module(builder)


class Week8CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="week8-candidate-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        self.plan = builder.test_plan()
        self.provenance = {"manifest_sha256": "a" * 64, "raw_pngs": []}

    def write(self, relative, text="fixture\n"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def fixture(self):
        for relative in builder.RUNTIME_FILES + builder.EXTRA_DELIVERABLES:
            self.write(relative, "{}" if relative.endswith(".json") else "fixture\n")
        for record in self.plan:
            self.write(record["script"], "extends SceneTree\n# external packed verifier\n")
        self.write("project.godot", '[application]\nconfig/version="source"\nconfig/custom_user_dir_name="ProjectWuming"\nrun/main_scene="' + builder.MAIN + '"\ntextures/canvas_textures/default_texture_filter=0\n')
        self.write("game/presentation/characters/hero_visual.gd", "const ACTIVE_DATA_PATH := IMAGEGEN_DATA_PATH\n")
        rows = [{"id": identifier, "category": "内功" if identifier.startswith("IN_") else "外功", "ultimate": False} for identifier in builder.b6.SEED_IDS]
        self.write("game/content/data/battle_skills_tactics.json", json.dumps(rows))
        self.write(builder.REVIEW_SEED, "# Testers\n\n状态：候选尚未制作。\n\n实际独立参与人数：0／5。\n")
        for relative in builder.ENGINE_LICENSES:
            self.write(relative, "Full existing license fixture.\n" * 10)
        binary = self.write(builder.ENGINE_RELATIVE + "/" + builder.ENGINE_BINARY, "not an engine; never executed\n")
        binary.chmod(0o755)
        self.write(builder.ENGINE_RELATIVE + "/Contents/Info.plist", "original plist fixture")

    def preflight(self):
        with mock.patch.object(builder.art, "production_preflight", return_value=self.provenance):
            return builder.production_preflight(self.root, self.plan)

    def test_plan_has_all_ten_mandatory_gates(self):
        self.assertEqual(len(self.plan), 10)
        self.assertEqual({record["id"] for record in self.plan}, builder.REQUIRED_GATES)
        self.assertEqual(builder.REQUIRED_GATES, {"branch_rules", "branch_session", "anchors", "automatic", "flow", "ui", "world", "story", "martial", "character"})

    def test_plan_can_reorder_but_not_omit(self):
        path = self.write("plan.json", json.dumps(list(reversed(self.plan))))
        self.assertEqual(builder.test_plan(path), list(reversed(self.plan)))
        path.write_text(json.dumps(self.plan[:-1]))
        with self.assertRaisesRegex(ValueError, "gates missing"):
            builder.test_plan(path)

    def test_plan_cannot_replace_script_or_weaken_regex(self):
        for field, value in (("script", "game/tests/test_do_nothing.gd"), ("script", "../escape.gd"), ("marker", "^.*$"), ("marker", "PASS")):
            altered = [dict(record) for record in self.plan]
            altered[0][field] = value
            with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "cannot be weakened"):
                builder.test_plan(self.write("plan.json", json.dumps(altered)))

    def test_plan_rejects_unknown_duplicate_extra_and_bad_shape(self):
        variants = [self.plan + [self.plan[0]], [{**self.plan[0], "id": "unknown"}] + self.plan[1:],
                    [{**self.plan[0], "optional": True}] + self.plan[1:], {}, [None], [{"id": {}}]]
        for value in variants:
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.test_plan(self.write("plan.json", json.dumps(value)))

    def test_nonfinite_json_rejected(self):
        with self.assertRaisesRegex(ValueError, "Non-finite"):
            builder.read_json(self.write("plan.json", "[NaN]"))

    def test_preflight_covers_sources_runtime_licenses_and_art_without_writes(self):
        self.fixture()
        before = {str(path.relative_to(self.root)): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        ready = self.preflight()
        self.assertEqual(ready["active_character"], self.provenance)
        self.assertEqual(ready["martial_ids"], list(builder.b6.SEED_IDS))
        self.assertIn("game/persistence/save_service.gd", ready["runtime_source_inventory"])
        self.assertNotIn(self.plan[0]["script"], ready["runtime_source_inventory"])
        self.assertIn(builder.ENGINE_BINARY, ready["engine_inventory"])
        self.assertEqual(len(ready["engine_inventory_sha256"]), 64)
        self.assertEqual(before, {str(path.relative_to(self.root)): path.read_bytes() for path in self.root.rglob("*") if path.is_file()})

    def test_preflight_rejects_missing_new_deliverable(self):
        self.fixture()
        (self.root / "game/persistence/save_service.gd").unlink()
        with self.assertRaisesRegex(ValueError, "deliverable missing"):
            self.preflight()

    def test_preflight_rejects_missing_engine(self):
        self.fixture()
        (self.root / builder.ENGINE_RELATIVE / builder.ENGINE_BINARY).unlink()
        with self.assertRaisesRegex(ValueError, "executable is missing"):
            self.preflight()

    def test_preflight_requires_full_existing_license_files(self):
        self.fixture()
        self.write(builder.ENGINE_LICENSES[0], "short")
        with self.assertRaisesRegex(ValueError, "Full existing Godot license"):
            self.preflight()

    def test_engine_symlink_must_not_escape_app_bundle(self):
        app = self.root / "Fake.app"
        binary = self.write("Fake.app/Contents/MacOS/Godot", "fake never launched")
        binary.chmod(0o755)
        outside = self.write("outside", "private outside fixture")
        (app / "external").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            builder.engine_inventory(app)

    def test_preflight_keeps_active_hero_and_six_independent_arts(self):
        self.fixture()
        self.write("game/presentation/characters/hero_visual.gd", "const ACTIVE_DATA_PATH := DATA_PATH\n")
        with self.assertRaisesRegex(ValueError, "active imagegen"):
            self.preflight()
        self.write("game/presentation/characters/hero_visual.gd", "const ACTIVE_DATA_PATH := IMAGEGEN_DATA_PATH\n")
        path = self.root / "game/content/data/battle_skills_tactics.json"
        rows = json.loads(path.read_text())
        rows[0]["ultimate"] = True
        path.write_text(json.dumps(rows))
        with self.assertRaisesRegex(ValueError, "independent V1"):
            self.preflight()

    def test_preflight_rejects_duplicate_skill_identifiers(self):
        self.fixture()
        path = self.root / "game/content/data/battle_skills_tactics.json"
        rows = json.loads(path.read_text())
        path.write_text(json.dumps(rows + [rows[0]]))
        with self.assertRaisesRegex(ValueError, "unique strings"):
            self.preflight()

    def test_runtime_inventory_rejects_escaped_file(self):
        self.write("export_presets.cfg")
        outside = self.write("outside", "external target")
        external = Path(self.temp.name) / "external"
        external.write_text(outside.read_text())
        target = self.root / "game/content/escape.json"
        target.parent.mkdir(parents=True)
        target.symlink_to(external)
        with self.assertRaisesRegex(ValueError, "escapes project"):
            builder.runtime_inventory(self.root)

    def test_stage_changes_only_three_isolated_settings(self):
        before = 'config/version="source"\nconfig/custom_user_dir_name="ProjectWuming"\nrun/main_scene="' + builder.MAIN + '"\n'
        after = builder.stage_project_text(before)
        self.assertIn(builder.VERSION, after)
        self.assertIn(builder.SAVE_DIRECTORY, after)
        self.assertIn(builder.MAIN, after)
        self.assertNotIn(builder.VERSION, before)
        with self.assertRaisesRegex(ValueError, "Expected one"):
            builder.stage_project_text(before + 'config/version="duplicate"\n')

    def test_preflight_only_never_launches_or_builds(self):
        self.fixture()
        with mock.patch.object(builder.art, "production_preflight", return_value=self.provenance), mock.patch.object(builder.subprocess, "run") as run, mock.patch.object(builder.subprocess, "check_output") as query, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(builder.main(["--project-root", str(self.root), "--preflight-only"]), 0)
            run.assert_not_called()
            query.assert_not_called()
        self.assertIn("WEEK8_PREFLIGHT_PASS", output.getvalue())
        self.assertFalse((self.root / "builds").exists())

    def test_preflight_failure_never_claims_pass_or_writes(self):
        with contextlib.redirect_stderr(io.StringIO()) as output, mock.patch.object(builder.subprocess, "run") as run:
            self.assertEqual(builder.main(["--project-root", str(self.root), "--preflight-only"]), 1)
            run.assert_not_called()
        self.assertIn("WEEK8_PREFLIGHT_FAIL", output.getvalue())
        self.assertFalse((self.root / "builds").exists())

    def test_inventory_digest_is_stable_and_path_sensitive(self):
        self.assertEqual(builder.inventory_digest({"a": "1", "b": "2"}), builder.inventory_digest({"b": "2", "a": "1"}))
        self.assertNotEqual(builder.inventory_digest({"a": "1"}), builder.inventory_digest({"b": "1"}))

    def test_frozen_source_check_rejects_document_or_runtime_edit(self):
        self.fixture()
        ready = self.preflight()
        identity = {"commit": "a" * 40, "dirty": True, "status": " M test"}
        inputs = {builder.REVIEW_SEED: builder.art.sha256(self.root / builder.REVIEW_SEED)}
        with mock.patch.object(builder, "git_identity", return_value=identity), mock.patch.object(builder.art, "production_preflight", return_value=self.provenance):
            builder.verify_frozen_sources(self.root, ready, {}, inputs, identity)
            self.write(builder.REVIEW_SEED, "changed feedback")
            with self.assertRaisesRegex(ValueError, "changed during build"):
                builder.verify_frozen_sources(self.root, ready, {}, inputs, identity)

    def test_input_hashes_include_nested_review_attachments_and_all_licenses(self):
        self.fixture()
        self.write(builder.REVIEW_SEED, "# Feedback\n\n[Notes](./notes.md)\n")
        self.write("docs/notes.md", "# Notes\n\n![Evidence](./evidence.png)\n")
        self.write("docs/evidence.png", "fixture image; preflight does not render")
        self.write("licenses/ADDITIONAL.txt", "additional complete bundled license")
        ready = self.preflight()
        inputs = builder.source_input_hashes(self.root, ready)
        for relative in (builder.REVIEW_SEED, "docs/notes.md", "docs/evidence.png", "licenses/ADDITIONAL.txt"):
            self.assertEqual(inputs[relative], builder.art.sha256(self.root / relative))
        self.assertTrue(set(builder.EXTRA_DELIVERABLES).issubset(inputs))

    def test_frozen_nested_review_edit_rejected_when_dirty_status_is_unchanged(self):
        self.fixture()
        self.write(builder.REVIEW_SEED, "# Feedback\n\n[Notes](./notes.md)\n")
        self.write("docs/notes.md", "already dirty review notes\n")
        ready = self.preflight()
        inputs = builder.source_input_hashes(self.root, ready)
        identity = {"commit": "a" * 40, "dirty": True, "status": " M docs/notes.md"}
        with mock.patch.object(builder, "git_identity", return_value=identity), mock.patch.object(builder.art, "production_preflight", return_value=self.provenance):
            builder.verify_frozen_sources(self.root, ready, {}, inputs, identity)
            self.write("docs/notes.md", "different contents, same porcelain status\n")
            with self.assertRaisesRegex(ValueError, "changed during build"):
                builder.verify_frozen_sources(self.root, ready, {}, inputs, identity)

    def test_input_hashes_reject_escaped_review_attachment(self):
        self.fixture()
        outside = Path(self.temp.name) / "external.md"
        outside.write_text("outside review fixture\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "input missing or escapes root"):
            builder.source_input_hashes(self.root, {"review_files": ["../external.md"]})

    def test_positive_exact_zero_failure_gate_markers(self):
        marker = next(record["marker"] for record in self.plan if record["id"] == "automatic")
        good = "AUTOMATIC_SAVES: 236 checks, 0 failures\nAUTOMATIC_SAVES_PASS checks=236\n"
        self.assertIn("checks=236", builder.verify_log(self.write("pass.log", good), marker))
        for bad in (good + good, good.replace("236", "0"), good + "SCRIPT ERROR: malformed\n", good + "OTHER_FAIL unsafe\n",
                    good + "unrelated failures=1\n", good.replace("0 failures", "1 failures"), good + "CHECK_TIMEOUT\n"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                builder.verify_log(self.write("bad.log", bad), marker)

    def test_flow_and_ui_source_or_partial_markers_cannot_pass(self):
        flow = next(record["marker"] for record in self.plan if record["id"] == "flow")
        line = "WEEK8_FLOW_PASS checks=186 failures=0 packed=true phase= choice=home pid=123 fixture=user://tests/week8_flow_fixture\n"
        builder.verify_log(self.write("flow.log", line), flow)
        for bad in (line.replace("packed=true", "packed=false"), line.replace("failures=0", "failures=1"), line.replace("checks=186", "checks=0"), line + line):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                builder.verify_log(self.write("bad_flow.log", bad), flow)

    def test_capture_protocol_has_exact_36_files_and_37_calls(self):
        self.assertEqual(len(builder.CAPTURE_NAMES), 36)
        self.assertEqual(len(set(builder.CAPTURE_NAMES)), 36)
        self.assertEqual(builder.CAPTURE_CALLS, 37)
        self.assertIn("week8_zh_CN_home_progress_pending.png", builder.CAPTURE_NAMES)
        self.assertIn("week8_zh_CN_home_world_pending.png", builder.CAPTURE_NAMES)
        line = "WEEK8_BRANCH_UI_PASS checks=900 packed=true captures=37 (keyboard UI; fixture travel; legal scripted combat; not human UX/time)\n"
        builder.verify_log(self.write("capture.log", line), builder.CAPTURE_MARKER)
        with self.assertRaises(ValueError):
            builder.verify_log(self.write("bad_capture.log", line.replace("captures=37", "captures=36")), builder.CAPTURE_MARKER)

    def test_capture_evidence_requires_exact_set_and_640x360(self):
        folder = self.root / "evidence"
        folder.mkdir()
        for name in builder.CAPTURE_NAMES:
            (folder / name).write_bytes(b"synthetic fixture; dimensions mocked")
        with mock.patch.object(builder.art.validator, "read_png_info", return_value=SimpleNamespace(width=640, height=360)):
            builder.verify_captures(folder)
            (folder / "extra.png").write_bytes(b"fixture")
            with self.assertRaisesRegex(ValueError, "extra"):
                builder.verify_captures(folder)
            (folder / "extra.png").unlink()
            (folder / builder.CAPTURE_NAMES[0]).unlink()
            with self.assertRaisesRegex(ValueError, "missing"):
                builder.verify_captures(folder)
        (folder / builder.CAPTURE_NAMES[0]).write_bytes(b"fixture")
        with mock.patch.object(builder.art.validator, "read_png_info", return_value=SimpleNamespace(width=1280, height=720)), self.assertRaisesRegex(ValueError, "640x360"):
            builder.verify_captures(folder)

    @staticmethod
    def phase(phase, choice="home", fixture="user://tests/week8_flow_fixture", pid=101):
        return f"WEEK8_FLOW_PASS checks=90 failures=0 packed=true phase={phase} choice={choice} pid={pid} fixture={fixture}\n"

    def restart(self):
        return self.phase("write") + "WEEK8_FLOW_PHASE_EXITED phase=write choice=home pid=101 returncode=0\n" + self.phase("read", pid=202) + "WEEK8_FLOW_PHASE_EXITED phase=read choice=home pid=202 returncode=0\n"

    def test_cold_phase_requires_exact_route_fixture_and_one_positive_pid(self):
        fixture = "user://tests/week8_flow_fixture"
        line = self.phase("write")
        self.assertEqual(builder.cold_phase_pid(line, "write", "home", fixture), 101)
        for bad in (line + line, line.replace("packed=true", "packed=false"), line.replace("pid=101", "pid=0"), line.replace("choice=home", "choice=dock"), line.replace("fixture", "other"), line.replace("failures=0", "failures=2")):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                builder.cold_phase_pid(bad, "write", "home", fixture)

    def test_cold_restart_requires_exit_before_distinct_reader(self):
        good = self.restart()
        actual = builder.verify_cold_restart(good, "home", "user://tests/week8_flow_fixture")
        self.assertEqual((actual["writer_pid"], actual["reader_pid"]), (101, 202))
        variants = [good.replace("pid=202", "pid=101"), good.replace("phase=write choice=home pid=101 returncode=0\n", ""),
                    good.replace("returncode=0", "returncode=1"), good + self.phase("read", pid=202), good.replace("choice=home", "choice=dock"),
                    good + "WEEK8_FLOW_PHASE_EXITED phase=read choice=home pid=999 returncode=1\n"]
        write, exited, read, read_exited = good.splitlines(keepends=True)
        variants.append(write + read + exited + read_exited)
        for bad in variants:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                builder.verify_cold_restart(bad, "home", "user://tests/week8_flow_fixture")

    def test_same_pck_probe_checks_version_save_dir_resources_and_manifest(self):
        source = builder.pack_probe_source(self.provenance)
        for value in (builder.VERSION, builder.SAVE_DIRECTORY, builder.MAIN, "project.binary", "project.godot", self.provenance["manifest_sha256"], "failures=0 packed=true"):
            self.assertIn(value, source)

    def test_launcher_is_relocatable_uses_bundled_engine_and_forwards_arguments(self):
        source = builder.launcher_text()
        self.assertIn('cd "$(dirname "$0")"', source)
        self.assertIn('runtime/Godot.app/Contents/MacOS/Godot', source)
        self.assertIn(builder.BINARY + '.pck', source)
        self.assertIn('"$@"', source)
        self.assertNotIn(str(self.root), source)
        self.assertNotIn("tools/godot.sh", source)
        self.assertNotIn("/Applications/", source)

    def test_portable_probe_requires_native_main_not_only_engine_version(self):
        source = builder.portable_probe_source()
        for value in ('DisplayServer.get_name() == "headless"', "RenderingServer.force_draw(true)", builder.MAIN, "ContentDB", "native=true", builder.SAVE_DIRECTORY):
            self.assertIn(value, source)
        self.assertNotIn("await RenderingServer.frame_post_draw", source)

    def test_handoff_discloses_human_windows_and_signed_app_limits(self):
        source = builder.handoff_text({"commit": "a" * 40, "dirty": True})
        for value in ("0／5", "约30分钟", "待测", "未验Windows真机", "不是独立签名游戏App", "非Steam", "仓库外"):
            self.assertIn(value, source)
        self.assertIn("未提交修改", source)
        self.assertIn("Play-on-Mac.command", source)

    def test_packaged_playtest_keeps_zero_humans_and_updates_candidate_identity(self):
        records = "## 单人记录（每人复制一份）\n\n真人意见：开场很清楚，码头这里不明白。\n\n实际独立参与人数：0／5。\n"
        original = ("# Feedback\n\n状态：候选尚未制作。\n\n## 版本与环境（发出前由开发者填）\n\n"
                    "| 候选版本／构建目录 | old-candidate |\n| commit／dirty身份／PCK SHA | old-commit／old-pack-sha |\n"
                    "| ZIP | old-build.zip |\n| Windows真实运行／实体手柄 | 未验 |\n\n" + records)
        result = builder.packaged_playtest_text(original, {"commit": "a" * 40, "dirty": True, "pack_sha256": "b" * 64})
        self.assertIn(builder.VERSION, result)
        self.assertIn("a" * 40, result)
        self.assertIn("b" * 64, result)
        self.assertIn("dirty=true", result)
        self.assertIn("0／5", result)
        self.assertIn("不是本包自动通行的测量结果", result)
        self.assertNotIn("候选尚未制作", result)
        self.assertNotIn("[HANDOFF]", result)  # Collector must not resolve output links against source docs/.
        self.assertIn("候选尚未制作", original)
        self.assertTrue(result.endswith(records))
        for obsolete in ("old-candidate", "old-commit", "old-pack-sha", "old-build.zip", "| ZIP |"):
            self.assertNotIn(obsolete, result)

    def test_packaged_playtest_replaces_current_filled_environment_not_human_answers(self):
        old_commit = "ffed656f086abab8225fd4730e072cd7065c7867"
        old_pack = "758baae8c2ad12a6d2d132b32d11ebdd9cfd0160fa22f32e446a0d75c16910ee"
        old_zip_sha = "a08c1129624947ae7d734acdfc02036f249b7f1f5c0bb8288c6a93ea839f752a"
        prefix = "# 第八周内部试玩与反馈模板\n\n状态：旧包" + old_commit + "。\n\n## 给测试者的话\n\n请自然游玩，不需要穷举。\n\n"
        environment = ("## 实际候选版本与环境\n\n| 字段 | 实际值 |\n|---|---|\n"
                       "| 候选版本／构建目录 | builds/week8/old-filled-build/ |\n"
                       "| 可转发ZIP／SHA-256 | builds/week8/Wuming-Week8-VS01-ffed656.zip；" + old_zip_sha + " |\n"
                       "| commit／dirty身份 | 源提交`" + old_commit + "`；构建时`dirty=false` |\n"
                       "| PCK SHA-256 | `" + old_pack + "` |\n"
                       "| 工程检查、Mac运行证据 | 旧包159项SHA全通过 |\n\n旧包特有说明必须移除。\n\n")
        records = ("## 单人记录（每人复制一份）\n\n匿名编号：T01。\n\n"
                   "| 开始后，你觉得主角为什么要行动？ | 救父亲，但质证引导还不够。 |\n\n"
                   "## 开发者观察（不要先给测试者看解法）\n\n玩家在码头停留了4分钟。\n\n"
                   "## 首批反馈汇总\n\n实际独立参与人数：1／5。\n")
        result = builder.packaged_playtest_text(prefix + environment + records,
                    {"game_version": "0.8.1-next", "save_directory": "NextCandidateSaves", "commit": "c" * 40, "dirty": True, "pack_sha256": "d" * 64})
        self.assertIn("0.8.1-next", result)
        self.assertIn("NextCandidateSaves", result)
        self.assertIn("c" * 40, result)
        self.assertIn("d" * 64, result)
        self.assertIn("dirty=true", result)
        self.assertIn("请自然游玩，不需要穷举。", result)
        self.assertTrue(result.endswith(records))
        for obsolete in (old_commit, old_pack, old_zip_sha, "Wuming-Week8-VS01-ffed656.zip", "old-filled-build", "旧包159项", "旧包特有说明", "可转发ZIP"):
            self.assertNotIn(obsolete, result)

    def test_packaged_playtest_rejects_missing_or_duplicate_environment_sections(self):
        metadata = {"commit": "a" * 40, "dirty": False, "pack_sha256": "b" * 64}
        heading = "## 实际候选版本与环境\n\n"
        records = "## 单人记录（每人复制一份）\n\n真人答案保留。\n"
        for original in ("# Feedback\n\n" + records, heading + heading + records,
                         "## 版本与环境（发出前由开发者填）\n\n" + heading + records):
            with self.subTest(original=original), self.assertRaisesRegex(ValueError, "Exactly one candidate"):
                builder.packaged_playtest_text(original, metadata)

    def test_packaged_playtest_rejects_missing_or_unexpected_record_boundary(self):
        metadata = {"commit": "a" * 40, "dirty": False, "pack_sha256": "b" * 64}
        for tail in ("no next heading", "## 其他必须保留的章节\n\n## 单人记录\n"):
            with self.subTest(tail=tail), self.assertRaisesRegex(ValueError, "single-person records heading"):
                builder.packaged_playtest_text("## 实际候选版本与环境\n\n" + tail, metadata)


if __name__ == "__main__":
    unittest.main()
