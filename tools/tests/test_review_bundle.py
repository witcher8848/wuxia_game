#!/usr/bin/env python3
"""Review-bundle tests only: no engine, export, or Git mutation is performed."""
import importlib.util
import base64
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


BUILDER = Path(__file__).resolve().parents[1] / "build_week4_candidate.py"
spec = importlib.util.spec_from_file_location("candidate_builder", BUILDER)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

week5_spec = importlib.util.spec_from_file_location("imagegen_candidate_builder", BUILDER.with_name("build_week5_candidate.py"))
week5 = importlib.util.module_from_spec(week5_spec)
sys.modules[week5_spec.name] = week5
week5_spec.loader.exec_module(week5)


class ReviewBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="review-bundle-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project"
        self.out = Path(self.temporary.name) / "bundle"
        self.root.mkdir()
        self.seed = self.root / "docs/week5_playtest.md"

    def fixture(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, bytes):
            path.write_bytes(contents)
        else:
            path.write_text(contents)
        return path

    def collect(self, **kwargs):
        return builder.collect_review_bundle(self.root, self.seed, self.out, **kwargs)

    def test_recursive_documents_images_video_scripts_and_cycles(self):
        self.fixture("docs/week5_playtest.md", '原话：更接近，进一步推进。\n[评审](./art_reference/review.md#意见)\n')
        self.fixture("docs/art_reference/review.md", '[回试玩表](../week5_playtest.md)\n![图](./picture.png)\n[录像](./walk.mp4)\n[脚本](../../tools/preview.gd)\n')
        self.fixture("docs/art_reference/picture.png", b"image bytes")
        self.fixture("docs/art_reference/walk.mp4", b"movie bytes")
        self.fixture("tools/preview.gd", "extends SceneTree\n")
        documents = self.collect()
        self.assertEqual(len(documents), 2)
        self.assertEqual(builder.validate_review_bundle(self.out, documents), 5)
        self.assertEqual((self.out / "review/docs/art_reference/picture.png").read_bytes(), b"image bytes")
        self.assertEqual((self.out / "review/docs/art_reference/walk.mp4").read_bytes(), b"movie bytes")
        self.assertEqual((self.out / "review/tools/preview.gd").read_text(), "extends SceneTree\n")
        self.assertIn("更接近，进一步推进", (self.out / "PLAYTEST.md").read_text())
        self.assertIn("#意见", (self.out / "PLAYTEST.md").read_text())
        self.assertIn("../../../PLAYTEST.md", (self.out / "review/docs/art_reference/review.md").read_text())

    def test_external_links_anchors_and_code_are_preserved(self):
        contents = ('[网络](https://example.com/a_(b)?x=1#出处)\n'
                    '[邮件](mailto:review@example.com)\n[本页](#意见)\n'
                    '`[示例](./missing.png)`\n```markdown\n[示例](./also-missing.md)\n```\n')
        self.fixture("docs/week5_playtest.md", contents)
        documents = self.collect()
        self.assertEqual(builder.validate_review_bundle(self.out, documents), 0)
        self.assertEqual((self.out / "PLAYTEST.md").read_text(), contents)

    def test_angle_encoded_spaces_titles_and_reference_links(self):
        self.fixture("docs/week5_playtest.md", '[图](<./art_reference/a%20b.png> "标题")\n![另图][evidence]\n[evidence]: ./art_reference/a%20b.png "引用标题"\n')
        self.fixture("docs/art_reference/a b.png", b"space-name image")
        documents = self.collect()
        self.assertEqual(builder.validate_review_bundle(self.out, documents), 2)
        contents = (self.out / "PLAYTEST.md").read_text()
        self.assertIn('<./review/docs/art_reference/a%20b.png> "标题"', contents)
        self.assertIn('[evidence]: ./review/docs/art_reference/a%20b.png "引用标题"', contents)

    def test_generated_metadata_redirect_and_final_validation(self):
        self.fixture("docs/week5_playtest.md", '[信息](../11_week5_review.md#历史)\n')
        review = self.fixture("11_week5_review.md", '[不应递归](./missing-file.md)\n')
        documents = self.collect(redirects={review: self.out / "build_info.json"})
        self.assertEqual((self.out / "PLAYTEST.md").read_text(), '[信息](./build_info.json)\n')
        with self.assertRaisesRegex(ValueError, "not self-contained"):
            builder.validate_review_bundle(self.out, documents)
        (self.out / "build_info.json").write_text('{}\n')
        self.assertEqual(builder.validate_review_bundle(self.out, documents), 1)
        self.assertFalse((self.out / "review/11_week5_review.md").exists())

    def test_source_text_preserves_the_feedback_payload(self):
        self.fixture("docs/week5_playtest.md", "原磁盘文本\n")
        self.collect(source_text="当前反馈：待用户复核，不代签通过。\n")
        self.assertEqual((self.out / "PLAYTEST.md").read_text(), "当前反馈：待用户复核，不代签通过。\n")
        self.assertEqual(self.seed.read_text(), "原磁盘文本\n")

    def test_missing_link_fails_preflight_without_copies(self):
        self.fixture("docs/week5_playtest.md", '[好图](./good.png)\n[缺失](./missing.png)\n')
        self.fixture("docs/good.png", b"good")
        with self.assertRaisesRegex(ValueError, "Missing/out-of-project"):
            self.collect()
        self.assertFalse(self.out.exists())

    def test_relative_escape_is_rejected(self):
        outside = self.root.parent / "outside.png"
        outside.write_bytes(b"outside")
        self.fixture("docs/week5_playtest.md", '[越界](../../outside.png)\n')
        with self.assertRaisesRegex(ValueError, "Missing/out-of-project"):
            self.collect()
        self.assertFalse(self.out.exists())

    def test_symlink_escape_is_rejected(self):
        outside = self.root.parent / "outside.png"
        outside.write_bytes(b"outside")
        self.fixture("docs/week5_playtest.md", '[越界](./linked.png)\n')
        (self.root / "docs/linked.png").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "Missing/out-of-project"):
            self.collect()

    def test_destination_symlink_escape_is_rejected(self):
        self.fixture("docs/week5_playtest.md", '[图](./image.png)\n')
        self.fixture("docs/image.png", b"image")
        self.out.mkdir()
        outside = self.root.parent / "outside-dir"
        outside.mkdir()
        (self.out / "review").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Out-of-bundle"):
            self.collect()
        self.assertEqual(list(outside.iterdir()), [])

    def test_absolute_and_file_uri_links_are_rejected(self):
        for link in ("/tmp/private.png", "file:///tmp/private.png", "C:/private.png"):
            with self.subTest(link=link):
                self.fixture("docs/week5_playtest.md", f'[越界]({link})\n')
                with self.assertRaises(ValueError):
                    self.collect()

    def test_sensitive_or_non_review_files_are_rejected(self):
        for path in (".env", "export_credentials.cfg", "tools/run.sh", "docs/.private.json", "docs/.private/config.json"):
            with self.subTest(path=path):
                self.fixture(path, "do not package")
                self.fixture("docs/week5_playtest.md", f'[非评审](../{path})\n')
                with self.assertRaisesRegex(ValueError, "Not an allowed review"):
                    self.collect()

    def test_validation_rejects_removed_and_escaping_targets(self):
        self.fixture("docs/week5_playtest.md", '[图](./image.png)\n')
        self.fixture("docs/image.png", b"image")
        documents = self.collect()
        image = self.out / "review/docs/image.png"
        image.unlink()
        with self.assertRaisesRegex(ValueError, "not self-contained"):
            builder.validate_review_bundle(self.out, documents)
        (self.out / "PLAYTEST.md").write_text('[越界](../project/docs/image.png)\n')
        with self.assertRaisesRegex(ValueError, "not self-contained"):
            builder.validate_review_bundle(self.out, documents)


class CurrentRepositoryReviewTests(unittest.TestCase):
    def test_completion_audit_links_are_safe_to_include_in_review(self):
        root = BUILDER.parents[1]
        with tempfile.TemporaryDirectory(prefix="week5-audit-review-integration-") as temporary:
            out = Path(temporary) / "bundle"
            documents = builder.collect_review_bundle(
                root, root / "docs/week5_imagegen_completion_audit_20261012.md", out,
                redirects={root / "11_week5_review.md": out / "build_info.json"},
            )
            (out / "build_info.json").write_text('{}\n')
            self.assertGreater(builder.validate_review_bundle(out, documents), 100)
            self.assertIn("57 是逻辑槽数", (out / "PLAYTEST.md").read_text())
            self.assertFalse(any(out.rglob("*.pck")))

    def test_current_week5_review_is_self_contained_without_export(self):
        root = BUILDER.parents[1]
        with tempfile.TemporaryDirectory(prefix="week5-review-integration-") as temporary:
            out = Path(temporary) / "bundle"
            documents = builder.collect_review_bundle(
                root, root / "docs/week5_playtest.md", out,
                redirects={root / "11_week5_review.md": out / "build_info.json"},
            )
            (out / "build_info.json").write_text('{}\n')
            count = builder.validate_review_bundle(out, documents)
            self.assertGreaterEqual(len(documents), 10)
            self.assertGreater(count, 100)
            self.assertIn("动画演出没有什么问题，但是像素图不太好看", (out / "PLAYTEST.md").read_text())
            self.assertTrue((out / "review/docs/art_reference/protagonist_imagegen_walk_bagfix_review_20261011.md").is_file())
            self.assertTrue((out / "review/docs/art_reference/hero_imagegen_walk_20261010/single_frames_armfix_20261011/walk_loop_8fps.mp4").is_file())
            self.assertFalse((out / "docs").exists())
            self.assertFalse(any(out.rglob("*.pck")))
            print(f"CURRENT_REVIEW_BUNDLE_PASS documents={len(documents)} local_links={count} files={sum(path.is_file() for path in out.rglob('*'))}")


class ImagegenProductionPreflightTests(unittest.TestCase):
    """Synthetic 1-pixel PNGs are temporary structure fixtures, never game art."""
    PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1kAAAAASUVORK5CYII=")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="week5-production-preflight-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "project"
        self.root.mkdir()
        self.sources = self.root / "docs/art_reference"
        self.sources.mkdir(parents=True)
        (self.sources / "original.png").write_bytes(self.PNG)
        (self.root / "project.godot").write_text('[rendering]\ntextures/canvas_textures/default_texture_filter=0\n')
        self.manifest = {"schema_version": 2, "frame_count": 57, "frames": [], "clips": {}}
        digest = hashlib.sha256(self.PNG).hexdigest()
        for index in range(57):
            resource = f"res://assets/runtime/characters/imagegen/fixture_{index}.png"
            path = self.root / resource.removeprefix("res://")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.PNG)
            self.write_import(path)
            self.manifest["frames"].append({"texture": resource, "region": [0, 0, 1, 1],
                                             "display_size": [1, 1], "anchor": [0.5, 1], "source_sha256": digest,
                                             "source_reference": "docs/art_reference/original.png", "source_size": [1, 1]})
        cell = 0
        for direction in week5.validator.DIRECTIONS:
            first = cell
            for action, count in week5.validator.ACTION_COUNTS.items():
                self.manifest["clips"][f"{action}_{direction}"] = {
                    "cells": list(range(cell, cell + count)), "fps": week5.validator.ACTION_FPS[action], "loop": action == "walk"}
                cell += count
            self.manifest["clips"][f"idle_{direction}"] = {"cells": [first], "fps": 1, "loop": True}
        self.manifest["clips"]["down"] = {"cells": [56], "fps": 1, "loop": False}
        self.manifest_path = self.root / week5.MANIFEST_RESOURCE.removeprefix("res://")
        self.write_manifest()

    def write_manifest(self):
        self.manifest_path.write_text(json.dumps(self.manifest))

    def write_import(self, png, **overrides):
        parameters = dict(week5.IMPORT_PARAMETERS, **overrides)
        Path(str(png) + ".import").write_text('[params]\n' + '\n'.join(f'{key}={value}' for key, value in parameters.items()) + '\n')

    def texture(self, index=0):
        return self.root / self.manifest["frames"][index]["texture"].removeprefix("res://")

    def test_original_byte_parity_and_read_only_preflight(self):
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        result = week5.production_preflight(self.root)
        self.assertEqual(result["schema_version"], 2)
        self.assertEqual(result["frame_count"], 57)
        self.assertEqual(len(result["raw_pngs"]), 57)
        self.assertEqual(result["raw_pngs"][0]["originals"], ["original.png"])
        self.assertEqual(result["raw_pngs"][0]["size"], [1, 1])
        self.assertEqual(before, {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()})

    def test_missing_active_manifest_is_rejected_without_output(self):
        self.manifest_path.unlink()
        with self.assertRaisesRegex(ValueError, "manifest is not ready"):
            week5.production_preflight(self.root)
        self.assertFalse((self.root / "builds").exists())

    def test_manifest_raw_hash_mismatch_is_rejected(self):
        self.manifest["frames"][0]["source_sha256"] = "0" * 64
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "does not match"):
            week5.production_preflight(self.root)

    def test_no_matching_original_is_rejected(self):
        (self.sources / "original.png").write_bytes(b"different original")
        with self.assertRaisesRegex(ValueError, "No byte-identical original"):
            week5.production_preflight(self.root)

    def test_explicit_original_reference_and_dimensions_are_required(self):
        for key, value in (("source_reference", "docs/art_reference/missing.png"),
                           ("source_reference", "docs/art_reference/../private.png"),
                           ("source_size", [2, 1]), ("source_size", [True, 1])):
            with self.subTest(key=key, value=value):
                before = self.manifest["frames"][0][key]
                self.manifest["frames"][0][key] = value
                self.write_manifest()
                with self.assertRaisesRegex(ValueError, "source_reference|source_size"):
                    week5.production_preflight(self.root)
                self.manifest["frames"][0][key] = before
        self.write_manifest()

    def test_missing_original_directory_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "source directory missing"):
            week5.production_preflight(self.root, source_root=self.root / "missing")

    def test_original_symlink_escape_is_rejected(self):
        outside = self.root.parent / "private.png"
        outside.write_bytes(self.PNG)
        (self.sources / "escape.png").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            week5.production_preflight(self.root)

    def test_missing_import_file_is_rejected(self):
        Path(str(self.texture()) + ".import").unlink()
        with self.assertRaises(FileNotFoundError):
            week5.production_preflight(self.root)

    def test_import_symlink_escape_is_rejected(self):
        config = Path(str(self.texture()) + ".import")
        outside = self.root.parent / "private.import"
        outside.write_text(config.read_text())
        config.unlink()
        config.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "configuration escapes"):
            week5.production_preflight(self.root)

    def test_all_original_alpha_import_parameters_are_mandatory(self):
        for key, expected in week5.IMPORT_PARAMETERS.items():
            with self.subTest(key=key):
                self.write_import(self.texture(), **{key: "true" if expected == "false" else "9"})
                with self.assertRaisesRegex(ValueError, "Original-alpha import required"):
                    week5.production_preflight(self.root)
        self.write_import(self.texture())

    def test_missing_import_parameter_is_rejected(self):
        config = Path(str(self.texture()) + ".import")
        config.write_text(config.read_text().replace("process/size_limit=0\n", ""))
        with self.assertRaisesRegex(ValueError, "process/size_limit"):
            week5.production_preflight(self.root)

    def test_duplicate_import_parameter_is_rejected(self):
        config = Path(str(self.texture()) + ".import")
        config.write_text(config.read_text() + "process/size_limit=0\n")
        with self.assertRaisesRegex(ValueError, "Duplicate texture import"):
            week5.production_preflight(self.root)

    def test_nearest_project_filter_is_required(self):
        (self.root / "project.godot").write_text('[rendering]\ntextures/canvas_textures/default_texture_filter=1\n')
        with self.assertRaisesRegex(ValueError, "nearest filtering"):
            week5.production_preflight(self.root)

    def stage(self):
        stage = self.root.parent / "stage"
        shutil.copytree(self.root / "assets", stage / "assets")
        shutil.copy2(self.root / "project.godot", stage / "project.godot")
        return stage

    def test_staging_preserves_png_bytes_without_source_assets(self):
        before = week5.production_preflight(self.root)
        stage = self.stage()
        week5.verify_stage_images(stage, before, self.sources)
        self.assertFalse((stage / "docs").exists())
        self.assertEqual(self.texture().read_bytes(), (stage / self.manifest["frames"][0]["texture"].removeprefix("res://")).read_bytes())

    def test_staging_cannot_mutate_manifest_even_if_structure_still_valid(self):
        before = week5.production_preflight(self.root)
        stage = self.stage()
        changed = self.manifest.copy()
        changed["notes"] = "stage changed metadata"
        (stage / week5.MANIFEST_RESOURCE.removeprefix("res://")).write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "changed active manifest"):
            week5.verify_stage_images(stage, before, self.sources)

    def test_staging_cannot_enable_alpha_fix(self):
        before = week5.production_preflight(self.root)
        stage = self.stage()
        png = stage / self.manifest["frames"][0]["texture"].removeprefix("res://")
        self.write_import(png, **{"process/fix_alpha_border": "true"})
        with self.assertRaisesRegex(ValueError, "fix_alpha_border"):
            week5.verify_stage_images(stage, before, self.sources)

    def test_source_digest_includes_import_policy_but_excludes_cache(self):
        stage = self.stage()
        first = week5.stage_source_digest(stage)
        cache = stage / ".godot/imported/cache.ctex"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"generated cache")
        self.assertEqual(first, week5.stage_source_digest(stage))
        png = stage / self.manifest["frames"][0]["texture"].removeprefix("res://")
        self.write_import(png, **{"process/fix_alpha_border": "true"})
        self.assertNotEqual(first, week5.stage_source_digest(stage))

    def test_checksum_covers_nested_files_and_not_its_own_manifest(self):
        out = self.root.parent / "output"
        (out / "evidence").mkdir(parents=True)
        (out / "evidence/scene.png").write_bytes(self.PNG)
        (out / "evidence/SHA256SUMS.txt").write_text("a nested attachment is still covered")
        (out / "SHA256SUMS.txt").write_text("old manifest")
        sums = week5.write_checksums(out)
        self.assertEqual(len(sums), 2)
        self.assertTrue(any(line.endswith("evidence/SHA256SUMS.txt") for line in sums))
        self.assertFalse(any(line.endswith("  SHA256SUMS.txt") for line in sums))

    def test_pe_architecture_is_checked_without_running_executable(self):
        executable = self.root.parent / "fixture.exe"
        data = bytearray(70)
        data[0:2] = b"MZ"
        data[60:64] = (64).to_bytes(4, "little")
        data[64:70] = b"PE\0\0\x64\x86"
        executable.write_bytes(data)
        week5.verify_pe(executable)
        executable.write_bytes(data[:-2] + b"\x4c\x01")
        with self.assertRaisesRegex(ValueError, "Not Windows x86_64"):
            week5.verify_pe(executable)

    def test_active_pass_marker_requires_pack_and_complete_capture_count(self):
        log = self.root.parent / "active.log"
        log.write_text("CHARACTER_IMAGEGEN_PIPELINE_PASS checks=400 packed=true captures=14\n")
        week5.verify_active_log(log, captures=14)
        for text in ("normal exit; no final marker\n",
                     "CHARACTER_IMAGEGEN_PIPELINE_PASS checks=400 packed=false captures=14\n",
                     "CHARACTER_IMAGEGEN_PIPELINE_PASS checks=400 packed=true captures=1\n",
                     "CHARACTER_IMAGEGEN_PIPELINE_PASS checks=0 packed=true captures=14\n"):
            log.write_text(text)
            with self.assertRaisesRegex(ValueError, "PASS marker"):
                week5.verify_active_log(log, captures=14)

    def test_capture_evidence_requires_exact_full_file_set_and_dimensions(self):
        folder = self.root.parent / "evidence"
        folder.mkdir()
        for name in week5.EXPECTED_CAPTURES:
            (folder / name).write_bytes(self.PNG)
        with mock.patch.object(week5.validator, "read_png_info", return_value=week5.validator.PngInfo(640, 360, "0" * 64)):
            week5.verify_capture_evidence(folder)
            (folder / "battle.png").unlink()
            with self.assertRaisesRegex(ValueError, "exact 14"):
                week5.verify_capture_evidence(folder)
            (folder / "battle.png").write_bytes(self.PNG)
            (folder / "unexpected.png").write_bytes(self.PNG)
            with self.assertRaisesRegex(ValueError, "unexpected"):
                week5.verify_capture_evidence(folder)
        (folder / "unexpected.png").unlink()
        with self.assertRaisesRegex(ValueError, "not 640x360"):
            week5.verify_capture_evidence(folder)


if __name__ == "__main__":
    unittest.main()
