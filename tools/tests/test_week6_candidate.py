"""Read-only preflight / evidence contract tests; never launch an engine/build."""
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

SCRIPT = Path(__file__).resolve().parents[1]/"build_week6_candidate.py"
spec = importlib.util.spec_from_file_location("week6_candidate_tests", SCRIPT)
builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = builder
spec.loader.exec_module(builder)


class Week6CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="week6-candidate-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)/"project"
        self.root.mkdir()
        self.provenance = {"manifest_sha256": "a"*64, "raw_pngs": []}
        self.plan = builder.test_plan()

    def write(self, relative, value="stub\n"):
        path = self.root/relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding="utf-8")
        return path

    def fixture(self):
        for relative in builder.NEW_RUNTIME_FILES:
            self.write(relative, "{}" if relative.endswith(".json") else "extends RefCounted\n")
        for entry in self.plan: self.write(entry["script"], '# accepts "--require-pack"\n')
        for relative in ("12_week6_review.md", "docs/week6_playtest.md", "tools/audit_pack.gd",
                         "tools/check_story_persistence.py", "tools/check_martial_persistence.py",
                         "game/tests/test_week6_martial_persistence.gd", "tools/build_hero_imagegen_manifest.py"):
            self.write(relative)
        self.write("project.godot", '[application]\nconfig/version="source"\nconfig/custom_user_dir_name="original"\nrun/main_scene="'+builder.MAIN+'"\n')
        self.write("game/presentation/characters/hero_visual.gd", "const ACTIVE_DATA_PATH := IMAGEGEN_DATA_PATH\n")
        rows = [{"id": identifier, "category": "内功" if identifier.startswith("IN_") else "外功", "ultimate": False} for identifier in builder.SEED_IDS]
        self.write("game/content/data/battle_skills.json", json.dumps(rows))
        self.write("game/content/data/enemy_archetypes.json", json.dumps({identifier: {} for identifier in ["EN_YAMEN_BLADE", "EN_YAMEN_BOW", "EN_YAMEN_CATCHER"]}))

    def preflight(self):
        with mock.patch.object(builder.art, "production_preflight", return_value=self.provenance):
            return builder.production_preflight(self.root, self.plan)

    def test_default_plan_covers_every_required_gate(self):
        self.assertEqual(len(self.plan), 10)
        self.assertEqual({record["id"] for record in self.plan}, builder.REQUIRED_GATES)
        self.assertEqual(len(builder.CAPTURE_PLANS), 4)
        self.assertEqual([len(record["files"]) for record in builder.CAPTURE_PLANS], [14, 12, 3, 5])

    def test_configurable_plan_cannot_drop_gate(self):
        path = self.write("plan.json", json.dumps(self.plan[:-1]))
        with self.assertRaisesRegex(ValueError, "gates missing"): builder.test_plan(path)

    def test_configurable_plan_allows_supported_script_change(self):
        self.plan[0]["script"] = "game/tests/test_alternate_martial.gd"
        path = self.write("plan.json", json.dumps(self.plan))
        self.assertEqual(builder.test_plan(path)[0]["script"], self.plan[0]["script"])

    def test_configurable_plan_rejects_duplicate_gate(self):
        path = self.write("plan.json", json.dumps(self.plan+[self.plan[0]]))
        with self.assertRaisesRegex(ValueError, "duplicate"): builder.test_plan(path)

    def test_configurable_plan_rejects_unknown_gate(self):
        self.plan[0]["id"] = "skip_everything"
        path = self.write("plan.json", json.dumps(self.plan))
        with self.assertRaisesRegex(ValueError, "Unknown"): builder.test_plan(path)

    def test_configurable_plan_rejects_escape_absolute_and_tools(self):
        for value in ("../outside.gd", "/outside.gd", "game/tests/../tools/test.gd", "game/tests/a\\b.gd", "game/tools/test.gd", "game/tests//test.gd"):
            with self.subTest(value=value):
                changed = [dict(record) for record in self.plan]
                changed[0]["script"] = value
                with self.assertRaisesRegex(ValueError, "canonical"): builder.test_plan(self.write("plan.json", json.dumps(changed)))

    def test_configurable_plan_rejects_unanchored_pass_regex(self):
        self.plan[0]["marker"] = "PASS"
        with self.assertRaisesRegex(ValueError, "complete log line"): builder.test_plan(self.write("plan.json", json.dumps(self.plan)))

    def test_configurable_plan_rejects_extra_fields(self):
        self.plan[0]["optional"] = True
        with self.assertRaisesRegex(ValueError, "only"): builder.test_plan(self.write("plan.json", json.dumps(self.plan)))

    def test_nonfinite_json_rejected(self):
        with self.assertRaisesRegex(ValueError, "Non-finite"): builder.read_json(self.write("plan.json", "[NaN]"))

    def test_preflight_tracks_six_definitions_three_enemies_and_identity(self):
        self.fixture()
        before = sorted(path.relative_to(self.root).as_posix() for path in self.root.rglob("*"))
        ready = self.preflight()
        self.assertEqual(ready["martial_ids"], list(builder.SEED_IDS))
        self.assertEqual(len(ready["enemy_ids"]), 3)
        self.assertEqual(ready["active_character"], self.provenance)
        self.assertEqual(len(ready["runtime_source_sha256"]), len(builder.NEW_RUNTIME_FILES))
        self.assertEqual(before, sorted(path.relative_to(self.root).as_posix() for path in self.root.rglob("*")))

    def test_preflight_rejects_missing_deliverable(self):
        self.fixture()
        (self.root/"12_week6_review.md").unlink()
        with self.assertRaisesRegex(ValueError, "deliverable missing"): self.preflight()

    def test_preflight_rejects_test_without_pack_guard(self):
        self.fixture()
        self.write(self.plan[0]["script"], "extends SceneTree\n")
        with self.assertRaisesRegex(ValueError, "require-pack"): self.preflight()

    def test_preflight_rejects_legacy_default_hero(self):
        self.fixture()
        self.write("game/presentation/characters/hero_visual.gd", "const ACTIVE_DATA_PATH := DATA_PATH\n")
        with self.assertRaisesRegex(ValueError, "Shared default"): self.preflight()

    def test_preflight_rejects_renamed_or_duplicate_martial(self):
        self.fixture()
        source = self.root/"game/content/data/battle_skills.json"
        rows = json.loads(source.read_text())
        source.write_text(json.dumps(rows+[rows[0]]))
        with self.assertRaisesRegex(ValueError, "unique"): self.preflight()
        source.write_text(json.dumps(rows[:-1]))
        with self.assertRaisesRegex(ValueError, "independent V1"): self.preflight()

    def test_preflight_does_not_count_ultimate_as_a_martial(self):
        self.fixture()
        path = self.root/"game/content/data/battle_skills.json"
        rows = json.loads(path.read_text())
        rows[0]["ultimate"] = True
        path.write_text(json.dumps(rows))
        with self.assertRaisesRegex(ValueError, "independent V1"): self.preflight()

    def test_preflight_rejects_two_enemy_templates(self):
        self.fixture()
        self.write("game/content/data/enemy_archetypes.json", '{"EN_YAMEN_BLADE":{},"EN_YAMEN_BOW":{}}')
        with self.assertRaisesRegex(ValueError, "Three enemy"): self.preflight()

    def test_preflight_rejects_changed_source_main(self):
        self.fixture()
        self.write("project.godot", 'run/main_scene="'+builder.TRIAL+'"\n')
        with self.assertRaisesRegex(ValueError, "Normal source main"): self.preflight()

    def test_readonly_main_does_not_invoke_engine_or_make_output(self):
        self.fixture()
        with mock.patch.object(builder.art, "production_preflight", return_value=self.provenance), mock.patch.object(builder.subprocess, "run") as run, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(builder.main(["--project-root", str(self.root), "--preflight-only"]), 0)
            run.assert_not_called()
        self.assertIn("WEEK6_PREFLIGHT_PASS", output.getvalue())
        self.assertFalse((self.root/"builds").exists())

    def test_readonly_failure_never_prints_pass_or_writes(self):
        with mock.patch.object(builder.art, "production_preflight", side_effect=ValueError("missing active manifest")), mock.patch.object(builder.subprocess, "run") as run, contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(builder.main(["--project-root", str(self.root), "--preflight-only"]), 1)
            run.assert_not_called()
        self.assertIn("WEEK6_PREFLIGHT_FAIL", output.getvalue())
        self.assertNotIn("WEEK6_PREFLIGHT_PASS", output.getvalue())
        self.assertFalse((self.root/"builds").exists())

    def test_review_graph_checks_links_without_copying(self):
        self.write("docs/week6_playtest.md", '[review](../12_week6_review.md)\n[image](./picture.png)\n')
        self.write("12_week6_review.md", '[historical context not recursively packaged](./missing.md)\n')
        self.write("docs/picture.png", "fixture bytes")
        sources = builder.review_preflight(self.root, self.root/"docs/week6_playtest.md")
        self.assertEqual(sources, ["12_week6_review.md", "docs/picture.png", "docs/week6_playtest.md"])
        self.assertFalse((self.root/"PLAYTEST.md").exists())

    def test_review_missing_or_python_attachment_fails(self):
        seed = self.write("docs/week6_playtest.md", '[missing](./missing.png)')
        with self.assertRaisesRegex(ValueError, "Missing/out-of-project"): builder.review_preflight(self.root, seed)
        self.write("tools/run.py", "pass")
        seed.write_text('[script](../tools/run.py)')
        with self.assertRaisesRegex(ValueError, "allowed review"): builder.review_preflight(self.root, seed)

    def test_stage_settings_are_isolated_but_normal_main_preserved(self):
        contents = 'config/version="source"\nconfig/custom_user_dir_name="original"\nrun/main_scene="'+builder.MAIN+'"\n'
        after = builder.stage_project_text(contents)
        self.assertIn('config/version="'+builder.VERSION+'"', after)
        self.assertIn('config/custom_user_dir_name="'+builder.SAVE_DIRECTORY+'"', after)
        self.assertIn('run/main_scene="'+builder.MAIN+'"', after)
        self.assertNotIn(builder.VERSION, contents)

    def test_stage_duplicate_setting_fails(self):
        with self.assertRaisesRegex(ValueError, "Expected one"): builder.stage_project_text('config/version="a"\nconfig/version="b"\n')

    def test_unique_complete_positive_pass_marker_required(self):
        marker = builder.DEFAULT_TESTS[2]["marker"]
        good = "WEEK6_BATTLE_PREVIEW_PASS checks=315 packed=true captures=0\n"
        path = self.write("evidence.log", good)
        self.assertIn("checks=315", builder.verify_log(path, marker))
        for invalid in (good+good, good.replace("315", "0"), good.replace("packed=true", "packed=false"), "partial screenshots only\n", good+"SCRIPT ERROR: bad\n"):
            with self.subTest(invalid=invalid):
                path.write_text(invalid)
                with self.assertRaises(ValueError): builder.verify_log(path, marker)

    def test_capture_marker_rejects_missing_or_wrong_count(self):
        capture = builder.CAPTURE_PLANS[1]
        path = self.write("render.log", "WEEK6_BATTLE_PREVIEW_PASS checks=340 packed=true captures=12\n")
        builder.verify_log(path, capture["marker"])
        path.write_text("WEEK6_BATTLE_PREVIEW_PASS checks=340 packed=true captures=11\n")
        with self.assertRaises(ValueError): builder.verify_log(path, capture["marker"])

    def test_pack_listing_uses_real_resource_positive_count(self):
        path = self.write("audit.log", "PACK_AUDIT_PASS resources=88 required=34\n")
        builder.verify_log(path, r"^PACK_AUDIT_PASS resources=[1-9]\d* required=[1-9]\d*\s*$")

    def test_exact_native_capture_set_required(self):
        folder = self.root/"evidence"
        folder.mkdir()
        for name in builder.PREPARATION_NAMES: (folder/name).write_bytes(b"synthetic unit fixture")
        with mock.patch.object(builder.art.validator, "read_png_info", return_value=SimpleNamespace(width=640, height=360)):
            builder.verify_captures(folder, builder.PREPARATION_NAMES)
            (folder/"extra.png").write_bytes(b"fixture")
            with self.assertRaisesRegex(ValueError, "extra"): builder.verify_captures(folder, builder.PREPARATION_NAMES)
            (folder/"extra.png").unlink()
        with mock.patch.object(builder.art.validator, "read_png_info", return_value=SimpleNamespace(width=1280, height=720)):
            with self.assertRaisesRegex(ValueError, "640x360"): builder.verify_captures(folder, builder.PREPARATION_NAMES)

    def test_missing_capture_set_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "missing"): builder.verify_captures(self.root/"absent", builder.TRIAL_NAMES)

    def test_probe_enforces_settings_source_overlay_and_manifest_identity(self):
        text = builder.pack_probe_source(self.provenance)
        for value in (builder.VERSION, builder.SAVE_DIRECTORY, builder.MAIN, builder.TRIAL, self.provenance["manifest_sha256"], "project.binary", "project.godot", "checks += 1"):
            self.assertIn(value, text)
        self.assertNotIn("checks=8", text)

    def test_launchers_target_same_pack_without_repointing_source(self):
        normal = builder.launcher_text(self.root)
        trial = builder.launcher_text(self.root, builder.TRIAL)
        self.assertIn(builder.BINARY+".pck", normal)
        self.assertIn(builder.BINARY+".pck", trial)
        self.assertNotIn(builder.TRIAL, normal)
        self.assertIn(builder.TRIAL, trial)

    def test_handoff_is_explicit_about_platform_and_same_package_evidence(self):
        text = builder.handoff_text({"commit": "a"*40, "dirty": False})
        for value in ("Windows 真机", "不是独立 macOS", "不是 Steam", "本包 metadata", builder.SAVE_DIRECTORY, "./PLAYTEST.md", "./build_info.json"):
            self.assertIn(value, text)
        self.assertIn("干净", text)

    def test_six_martial_and_ai_require_final_packed_pass(self):
        for index, text in ((0, "MARTIAL_LOADOUT_PASS checks=353 packed=true\n"), (1, "WEEK6_AI_PASS packed=true checks=709\n")):
            builder.verify_log(self.write("pass.log", text), self.plan[index]["marker"])
            with self.assertRaises(ValueError):
                builder.verify_log(self.write("pass.log", text.replace("packed=true", "packed=false")), self.plan[index]["marker"])


if __name__ == "__main__":
    unittest.main()
