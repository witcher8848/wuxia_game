"""Isolated schema-2 tests: temporary PNG fixtures only, no production writes."""
from __future__ import annotations

import base64
import copy
import hashlib
import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate_hero_manifest.py"
SPEC = importlib.util.spec_from_file_location("hero_manifest_validator", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)

# A real 1x1 PNG. Distinct temporary filenames exercise texture/region identity;
# this does NOT claim distinct filenames guarantee distinct visible poses.
PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
PNG_HASH = hashlib.sha256(PNG_BYTES).hexdigest()


class HeroManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory(prefix="hero_manifest_tests_")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.textures = self.root / "assets/runtime/characters"
        self.textures.mkdir(parents=True)
        frames = []
        for index in range(57):
            filename = f"fixture_{index:02d}.png"
            (self.textures / filename).write_bytes(PNG_BYTES)
            frames.append({
                "id": f"frame_{index}",
                "texture": f"res://assets/runtime/characters/{filename}",
                "region": [0, 0, 1, 1],
                "display_size": [48, 48],
                "anchor": [24, 44],
                "source_sha256": PNG_HASH,
            })
        clips = {}
        cell = 0
        for direction in validator.DIRECTIONS:
            for action, count in validator.ACTION_COUNTS.items():
                clips[f"{action}_{direction}"] = {
                    "cells": list(range(cell, cell + count)),
                    "fps": validator.ACTION_FPS[action],
                    "loop": action == "walk",
                }
                cell += count
            clips[f"idle_{direction}"] = {
                "cells": [clips[f"walk_{direction}"]["cells"][0]], "fps": 1, "loop": True,
            }
        clips["down"] = {"cells": [cell], "fps": 1, "loop": False}
        self.manifest = {
            "schema_version": 2,
            "frame_count": 57,
            "nominal_display_size": [48, 72],
            "frames": frames,
            "clips": clips,
        }

    def errors(self, manifest=None):
        return validator.validate_manifest(self.manifest if manifest is None else manifest, self.root)

    def assert_error(self, expected: str) -> None:
        errors = self.errors()
        self.assertTrue(any(expected in error for error in errors), errors)

    def duplicate_idle_image(self, action: str, direction="down") -> None:
        idle_cell = self.manifest["clips"][f"idle_{direction}"]["cells"][0]
        for cell in self.manifest["clips"][f"{action}_{direction}"]["cells"]:
            self.manifest["frames"][cell]["texture"] = self.manifest["frames"][idle_cell]["texture"]

    def test_valid_manifest_and_png_header(self):
        self.assertEqual(self.errors(), [])
        info = validator.read_png_info(self.textures / "fixture_00.png")
        self.assertEqual((info.width, info.height, info.sha256), (1, 1, PNG_HASH))

    def test_nominal_size_does_not_force_frame_display_size(self):
        self.manifest["nominal_display_size"] = [32, 48]
        self.assertEqual(self.errors(), [])

    def test_optional_ids_and_nominal_size(self):
        self.manifest.pop("nominal_display_size")
        for frame in self.manifest["frames"]:
            frame.pop("id")
        self.assertEqual(self.errors(), [])

    def test_validation_does_not_mutate_inputs_or_write_files(self):
        before_manifest = copy.deepcopy(self.manifest)
        before_files = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(self.errors(), [])
        self.assertEqual(self.manifest, before_manifest)
        after_files = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(after_files, before_files)

    def test_non_object_manifest(self):
        self.assertIn("manifest must be a JSON object", self.errors([]))

    def test_schema_and_frame_count(self):
        for field, value in [("schema_version", 1), ("schema_version", True), ("frame_count", 56), ("frame_count", True)]:
            with self.subTest(field=field, value=value):
                data = copy.deepcopy(self.manifest)
                data[field] = value
                self.assertTrue(any(field in error for error in self.errors(data)))

    def test_frame_array_count_and_shape(self):
        self.manifest["frames"].pop()
        self.assert_error("exactly 57")
        self.manifest["frames"] = {}
        self.assert_error("frames must be an array")

    def test_frame_object_and_required_fields(self):
        self.manifest["frames"][0] = None
        self.assert_error("frames[0] must be an object")
        self.manifest["frames"][0] = {}
        for field in ("texture", "region", "display_size", "anchor", "source_sha256"):
            self.assert_error(f"frames[0].{field}")

    def test_ids_are_valid_and_unique(self):
        for value in ("", " ", 0, True):
            with self.subTest(value=value):
                self.manifest["frames"][0]["id"] = value
                self.assert_error("id must be a nonempty string")
        self.manifest["frames"][0]["id"] = self.manifest["frames"][1]["id"]
        self.assert_error("duplicates another frame id")

    def test_region_integer_positive_and_bounds(self):
        invalid_regions = [None, [0, 0, 1], [-1, 0, 1, 1], [0, 0, 0, 1], [0, 0, 1, -1], [False, 0, 1, 1], [0, 0, 1.0, 1]]
        for region in invalid_regions:
            with self.subTest(region=region):
                self.manifest["frames"][0]["region"] = region
                self.assert_error("region must be")
        for region in ([1, 0, 1, 1], [0, 1, 1, 1], [0, 0, 2, 2]):
            self.manifest["frames"][0]["region"] = region
            self.assert_error("region exceeds PNG bounds")

    def test_display_size_positive_finite_and_equal_aspect(self):
        for display in (None, [48], [0, 0], [-1, -1], [True, True], [float("nan"), 1], [float("inf"), 1], [10**1000, 1]):
            with self.subTest(display=display):
                self.manifest["frames"][0]["display_size"] = display
                self.assert_error("display_size must contain")
        self.manifest["frames"][0]["display_size"] = [48, 72]
        self.assert_error("preserve the region aspect ratio")

    def test_anchor_finite_within_display_bounds(self):
        for anchor in (None, [1], [True, 1], [float("nan"), 1], [1, float("inf")]):
            self.manifest["frames"][0]["anchor"] = anchor
            self.assert_error("anchor must contain")
        for anchor in ([-1, 44], [24, -1], [49, 44], [24, 49]):
            self.manifest["frames"][0]["anchor"] = anchor
            self.assert_error("anchor must be inside")
        for anchor in ([0, 0], [48, 48], [24.5, 44.5]):
            self.manifest["frames"][0]["anchor"] = anchor
            self.assertEqual(self.errors(), [])

    def test_nominal_size_shape(self):
        self.manifest["nominal_display_size"] = [0, 72]
        self.assert_error("nominal_display_size must contain")

    def test_texture_resource_scope_and_canonical_path(self):
        invalid = [
            None, "/tmp/fixture.png", "file:///tmp/fixture.png", "res://docs/reference.png",
            "res://assets/runtime/characters/../fixture_00.png",
            "res://assets/runtime/characters/./fixture_00.png",
            "res://assets/runtime/characters//fixture_00.png",
            "res://assets/runtime/characters/sub\\fixture_00.png",
            "res://assets/runtime/characters/fixture_00.jpg",
            "res://assets/runtime/characters/missing.png",
        ]
        for resource in invalid:
            with self.subTest(resource=resource):
                self.manifest["frames"][0]["texture"] = resource
                self.assert_error("frames[0].texture")

    def test_symlink_cannot_escape_allowed_directory(self):
        external = self.root / "external.png"
        external.write_bytes(PNG_BYTES)
        (self.textures / "escape.png").symlink_to(external)
        self.manifest["frames"][0]["texture"] = "res://assets/runtime/characters/escape.png"
        self.assert_error("resolves outside assets/runtime/characters")

    def test_symlink_loop_is_reported_without_crashing(self):
        (self.textures / "loop_a.png").symlink_to("loop_b.png")
        (self.textures / "loop_b.png").symlink_to("loop_a.png")
        self.manifest["frames"][0]["texture"] = "res://assets/runtime/characters/loop_a.png"
        self.assert_error("frames[0].texture")

    def test_original_hash_format_and_mismatch(self):
        for digest in (None, "", "a" * 63, "G" * 64, PNG_HASH.upper()):
            self.manifest["frames"][0]["source_sha256"] = digest
            self.assert_error("source_sha256 must be")
        self.manifest["frames"][0]["source_sha256"] = "0" * 64
        self.assert_error("does not match the original PNG bytes")

    def test_invalid_png_signature_ihdr_and_crc(self):
        path = self.textures / "fixture_00.png"
        for contents in (b"not a png", PNG_BYTES[:25], PNG_BYTES[:8] + b"\x00\x00\x00\x0c" + PNG_BYTES[12:], PNG_BYTES[:29] + b"\0\0\0\0" + PNG_BYTES[33:]):
            path.write_bytes(contents)
            self.assert_error("frames[0].texture")

    def test_invalid_png_dimensions_and_methods(self):
        path = self.textures / "fixture_00.png"
        for offset, value in ((16, b"\0\0\0\0"), (24, b"\x03"), (25, b"\x07"), (26, b"\x01"), (27, b"\x01"), (28, b"\x02")):
            contents = bytearray(PNG_BYTES)
            contents[offset:offset + len(value)] = value
            contents[29:33] = struct.pack(">I", zlib.crc32(contents[12:29]) & 0xFFFFFFFF)
            path.write_bytes(contents)
            self.assert_error("frames[0].texture")

    def test_required_clips_and_unknown_actions(self):
        self.manifest["clips"].pop("slash_up")
        self.assert_error("clips.slash_up is required")
        self.manifest["clips"]["run_down"] = {"cells": [0], "fps": 1, "loop": True}
        self.assert_error("unexpected clip run_down")
        self.manifest["clips"] = None
        self.assert_error("clips must be an object")

    def test_clip_cells_count_type_and_range(self):
        for cells in (None, [0, 1, 2], [0, 1, 2, -1], [0, 1, 2, 57], [0, 1, 2, True], [0, 1, 2, 3.0]):
            self.manifest["clips"]["walk_down"]["cells"] = cells
            self.assert_error("clips.walk_down.cells must contain 4")

    def test_logical_slots_must_be_assigned_once(self):
        self.manifest["clips"]["strike_down"]["cells"] = [0, 5]
        self.assert_error("57 logical slots exactly once")

    def test_idle_reuses_first_walk_slot(self):
        self.manifest["clips"]["idle_down"]["cells"] = [1]
        self.assert_error("idle_down must reuse the first walk cell")

    def test_walk_requires_four_distinct_texture_regions(self):
        self.manifest["frames"][1]["texture"] = self.manifest["frames"][0]["texture"]
        self.assert_error("walk_down must use four distinct texture/region pairs")

    def test_each_basic_action_must_not_be_all_idle(self):
        original = copy.deepcopy(self.manifest)
        for action in ("strike", "thrust", "slash", "guard", "hit"):
            with self.subTest(action=action):
                self.manifest = copy.deepcopy(original)
                self.duplicate_idle_image(action)
                self.assert_error(f"clips.{action}_down must not consist entirely")

    def test_recovery_pose_may_reuse_idle(self):
        cell = self.manifest["clips"]["thrust_down"]["cells"][-1]
        self.manifest["frames"][cell]["texture"] = self.manifest["frames"][0]["texture"]
        self.assertEqual(self.errors(), [])

    def test_down_pose_must_not_be_idle(self):
        self.manifest["frames"][56]["texture"] = self.manifest["frames"][0]["texture"]
        self.assert_error("clips.down must not reuse an idle texture/region")

    def test_existing_timing_and_loop_contract(self):
        self.manifest["clips"]["walk_down"]["fps"] = 10
        self.assert_error("clips.walk_down.fps must remain 8")
        self.manifest["clips"]["thrust_left"]["loop"] = True
        self.assert_error("clips.thrust_left.loop must be false")
        self.manifest["clips"]["down"]["fps"] = True
        self.assert_error("clips.down.fps must remain 1")

    def test_duplicate_json_keys_are_rejected(self):
        path = self.root / "manifest.json"
        path.write_text('{"schema_version":2,"schema_version":2}', encoding="utf-8")
        self.assertTrue(any("duplicate JSON key" in error for error in validator.validate_manifest_file(path, self.root)))

    def test_missing_or_invalid_manifest_file(self):
        self.assertTrue(validator.validate_manifest_file(self.root / "missing.json", self.root))
        path = self.root / "manifest.json"
        path.write_text("{not valid json", encoding="utf-8")
        self.assertTrue(validator.validate_manifest_file(path, self.root))

    def test_cli_success_and_failure(self):
        path = self.root / "manifest.json"
        path.write_text(json.dumps(self.manifest), encoding="utf-8")
        arguments = [sys.executable, "-B", str(VALIDATOR_PATH), str(path), "--project-root", str(self.root)]
        result = subprocess.run(arguments, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HERO_MANIFEST_PASS", result.stdout)
        self.assertIn("NOT art or contract approval", result.stdout)
        self.manifest["frame_count"] = 56
        path.write_text(json.dumps(self.manifest), encoding="utf-8")
        result = subprocess.run(arguments, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("HERO_MANIFEST_FAIL", result.stderr)


if __name__ == "__main__":
    unittest.main()
