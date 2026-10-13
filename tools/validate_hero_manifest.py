#!/usr/bin/env python3
"""Read-only validation for the opt-in schema-2 protagonist frame manifest.

Frames reference unmodified PNGs under assets/runtime/characters. Their region
uses source-pixel coordinates; display_size and anchor use display coordinates.
Clips retain the existing integer ``cells`` interface and 57 logical slots.
This validates PNG headers, hashes and playback structure, not pixel-art quality,
alpha, palette, anatomy, animation naturalness or approval of a display contract.
It never writes, resizes, crops, quantizes or repairs any image or manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DIRECTIONS = ("down", "left", "right", "up")
ACTION_COUNTS = {"walk": 4, "strike": 2, "thrust": 3, "slash": 3, "guard": 1, "hit": 1}
ACTION_FPS = {"walk": 8, "strike": 10, "thrust": 10, "slash": 10, "guard": 3, "hit": 5}
FRAME_COUNT = 57
RESOURCE_PREFIX = "res://assets/runtime/characters/"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}\Z")


@dataclass(frozen=True)
class PngInfo:
    width: int
    height: int
    sha256: str


def read_png_info(path: Path) -> PngInfo:
    """Read IHDR and the original-file digest without decoding or changing pixels."""
    contents = path.read_bytes()
    if len(contents) < 33 or contents[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG with a complete IHDR")
    if contents[8:16] != b"\x00\x00\x00\rIHDR":
        raise ValueError("the first PNG chunk must be a 13-byte IHDR")
    if zlib.crc32(contents[12:29]) & 0xFFFFFFFF != struct.unpack(">I", contents[29:33])[0]:
        raise ValueError("invalid PNG IHDR checksum")
    width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", contents[16:29])
    allowed_depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
    if width <= 0 or height <= 0 or width > 0x7FFFFFFF or height > 0x7FFFFFFF:
        raise ValueError("invalid PNG dimensions")
    if color not in allowed_depths or depth not in allowed_depths[color]:
        raise ValueError("invalid PNG color type or bit depth")
    if compression != 0 or filtering != 0 or interlace not in (0, 1):
        raise ValueError("invalid PNG IHDR methods")
    return PngInfo(width, height, hashlib.sha256(contents).hexdigest())


def _integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _number(value: Any) -> bool:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _pair(value: Any, positive: bool = False) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(
        _number(item) and (not positive or item > 0) for item in value
    )


def _texture_path(resource: Any, root: Path) -> Path:
    if not isinstance(resource, str) or not resource.startswith(RESOURCE_PREFIX):
        raise ValueError("texture must be a res://assets/runtime/characters/ PNG")
    relative = resource.removeprefix("res://")
    if "\\" in relative or any(part in ("", ".", "..") for part in relative.split("/")):
        raise ValueError("texture path must be canonical, without traversal or backslashes")
    if Path(relative).suffix.lower() != ".png":
        raise ValueError("texture must have a .png extension")
    allowed = (root / "assets/runtime/characters").resolve()
    path = (root / relative).resolve()
    if not allowed.is_relative_to(root) or not path.is_relative_to(allowed):
        raise ValueError("texture resolves outside assets/runtime/characters")
    if not path.is_file():
        raise ValueError("texture PNG does not exist")
    return path


def validate_manifest(manifest: Any, project_root: str | Path) -> list[str]:
    """Return actionable errors; this function only reads referenced original PNGs."""
    errors: list[str] = []
    root = Path(project_root).resolve()
    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    if not _integer(manifest.get("schema_version")) or manifest["schema_version"] != 2:
        errors.append("schema_version must be 2")
    if not _integer(manifest.get("frame_count")) or manifest["frame_count"] != FRAME_COUNT:
        errors.append("frame_count must be 57 logical slots")
    if "nominal_display_size" in manifest and not _pair(manifest["nominal_display_size"], positive=True):
        errors.append("nominal_display_size must contain two finite positive numbers")

    frames = manifest.get("frames")
    if not isinstance(frames, list):
        return errors + ["frames must be an array indexed by integer clip cells"]
    if len(frames) != FRAME_COUNT:
        errors.append("frames must contain exactly 57 logical slots")
    png_cache: dict[Path, PngInfo | str] = {}
    identities: dict[int, tuple[Path, tuple[int, ...]]] = {}
    ids: set[str] = set()
    for index, frame in enumerate(frames):
        label = f"frames[{index}]"
        if not isinstance(frame, dict):
            errors.append(f"{label} must be an object")
            continue
        if "id" in frame:
            if not isinstance(frame["id"], str) or not frame["id"].strip():
                errors.append(f"{label}.id must be a nonempty string when present")
            elif frame["id"] in ids:
                errors.append(f"{label}.id duplicates another frame id")
            else:
                ids.add(frame["id"])
        region = frame.get("region")
        region_ok = isinstance(region, list) and len(region) == 4 and all(_integer(item) for item in region)
        if region_ok:
            region_ok = region[0] >= 0 and region[1] >= 0 and region[2] > 0 and region[3] > 0
            region_ok = region_ok and all(item <= 0x7FFFFFFF for item in region)
        if not region_ok:
            errors.append(f"{label}.region must be [x,y,width,height] with nonnegative integer position and positive integer size")
        display = frame.get("display_size")
        display_ok = _pair(display, positive=True)
        if not display_ok:
            errors.append(f"{label}.display_size must contain two finite positive numbers")
        elif region_ok and not math.isclose(display[0] / region[2], display[1] / region[3], rel_tol=1e-8, abs_tol=1e-8):
            errors.append(f"{label}.display_size must preserve the region aspect ratio")
        anchor = frame.get("anchor")
        if not _pair(anchor):
            errors.append(f"{label}.anchor must contain two finite numbers")
        elif display_ok and not (0 <= anchor[0] <= display[0] and 0 <= anchor[1] <= display[1]):
            errors.append(f"{label}.anchor must be inside or on the display bounds")
        source_hash = frame.get("source_sha256")
        hash_ok = isinstance(source_hash, str) and SHA256_PATTERN.fullmatch(source_hash) is not None
        if not hash_ok:
            errors.append(f"{label}.source_sha256 must be a lowercase 64-digit SHA-256")
        try:
            path = _texture_path(frame.get("texture"), root)
        except (OSError, RuntimeError, ValueError) as error:
            errors.append(f"{label}.texture: {error}")
            continue
        if path not in png_cache:
            try:
                png_cache[path] = read_png_info(path)
            except (OSError, ValueError) as error:
                png_cache[path] = str(error)
        info = png_cache[path]
        if isinstance(info, str):
            errors.append(f"{label}.texture: {info}")
            continue
        if hash_ok and source_hash != info.sha256:
            errors.append(f"{label}.source_sha256 does not match the original PNG bytes")
        if region_ok:
            if region[0] + region[2] > info.width or region[1] + region[3] > info.height:
                errors.append(f"{label}.region exceeds PNG bounds {info.width}x{info.height}")
            else:
                identities[index] = (path, tuple(region))

    clips = manifest.get("clips")
    if not isinstance(clips, dict):
        return errors + ["clips must be an object using integer cells"]
    expected: dict[str, tuple[int, int, bool]] = {}
    for direction in DIRECTIONS:
        for action, count in ACTION_COUNTS.items():
            expected[f"{action}_{direction}"] = (count, ACTION_FPS[action], action == "walk")
        expected[f"idle_{direction}"] = (1, 1, True)
    expected["down"] = (1, 1, False)
    for name in sorted(set(clips) - set(expected), key=str):
        errors.append(f"unexpected clip {name}; schema 2 keeps the fifth-week action set")
    valid_cells: dict[str, list[int]] = {}
    occupied: list[int] = []
    for name, (count, fps, loop) in expected.items():
        clip = clips.get(name)
        if not isinstance(clip, dict):
            errors.append(f"clips.{name} is required and must be an object")
            continue
        cells = clip.get("cells")
        cells_ok = isinstance(cells, list) and len(cells) == count and all(
            _integer(cell) and 0 <= cell < len(frames) for cell in cells
        )
        if not cells_ok:
            errors.append(f"clips.{name}.cells must contain {count} in-range integer frame indices")
        else:
            valid_cells[name] = cells
            if not name.startswith("idle_"):
                occupied.extend(cells)
        if not _number(clip.get("fps")) or clip["fps"] != fps:
            errors.append(f"clips.{name}.fps must remain {fps}")
        if not isinstance(clip.get("loop"), bool) or clip["loop"] != loop:
            errors.append(f"clips.{name}.loop must be {str(loop).lower()}")
    if sorted(occupied) != list(range(FRAME_COUNT)):
        errors.append("non-idle clips must assign each of the 57 logical slots exactly once")
    idle_identities: set[tuple[Path, tuple[int, ...]]] = set()
    for direction in DIRECTIONS:
        walk = valid_cells.get(f"walk_{direction}")
        idle = valid_cells.get(f"idle_{direction}")
        if walk is not None and idle is not None and idle != [walk[0]]:
            errors.append(f"clips.idle_{direction} must reuse the first walk cell")
        if walk is not None and all(cell in identities for cell in walk):
            if len({identities[cell] for cell in walk}) != 4:
                errors.append(f"clips.walk_{direction} must use four distinct texture/region pairs")
        if idle is None or idle[0] not in identities:
            continue
        idle_identity = identities[idle[0]]
        idle_identities.add(idle_identity)
        for action in ACTION_COUNTS:
            if action == "walk":
                continue
            name = f"{action}_{direction}"
            cells = valid_cells.get(name)
            if cells is not None and all(cell in identities for cell in cells):
                if all(identities[cell] == idle_identity for cell in cells):
                    errors.append(f"clips.{name} must not consist entirely of the idle texture/region")
    fallen = valid_cells.get("down")
    if fallen is not None and fallen[0] in identities and identities[fallen[0]] in idle_identities:
        errors.append("clips.down must not reuse an idle texture/region")
    return errors


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_manifest_file(path: str | Path, project_root: str | Path) -> list[str]:
    try:
        manifest = json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    except (OSError, UnicodeError, ValueError) as error:
        return [f"cannot read manifest: {error}"]
    return validate_manifest(manifest, project_root)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="schema-2 JSON manifest to read")
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args(argv)
    errors = validate_manifest_file(arguments.manifest, arguments.project_root)
    if errors:
        for error in errors:
            print(f"HERO_MANIFEST_FAIL {error}", file=sys.stderr)
        return 1
    print("HERO_MANIFEST_PASS schema_version=2 frames=57; read-only structure/hash check, NOT art or contract approval")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
