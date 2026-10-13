#!/usr/bin/env python3
"""Read-only alpha-connected-component measurements for original hero PNGs.

Prints JSON to stdout; never modifies or saves an image or source file. Uses only
Pillow plus the Python standard library. Regions are integer, exclusive-end
rectangles suitable for an AtlasTexture/GPU region; no masks or shaders.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from collections import defaultdict
from pathlib import Path

from PIL import Image


SOURCES = (
    ("combat_down", "protagonist_imagegen_combat_down_sheet_20261011.png", 2, 4),
    ("combat_left", "protagonist_imagegen_combat_left_sheet_20261011.png", 2, 4),
    ("combat_right", "protagonist_imagegen_combat_right_sheet_20261011_v3.png", 2, 4),
    ("combat_up", "protagonist_imagegen_combat_up_sheet_20261011.png", 2, 4),
    ("walk_down", "protagonist_imagegen_walk_down_sheet_20261011.png", 4, 1),
    ("walk_up", "protagonist_imagegen_walk_up_sheet_20261011.png", 4, 1),
    ("walk_left", "protagonist_imagegen_walk_left_sheet_20261011_v2.png", 4, 1),
    ("walk_right_0", "protagonist_imagegen_walk_right_pose0_restored_20261010.png", 1, 1),
    ("walk_right_1", "protagonist_imagegen_walk_right_pose1_restored_20261010.png", 1, 1),
    ("walk_right_2", "protagonist_imagegen_walk_right_pose2_consistent_20261010.png", 1, 1),
    ("walk_right_3", "protagonist_imagegen_walk_right_pose3_bagfix_20261011.png", 1, 1),
    ("defeat", "protagonist_imagegen_defeat_20261011.png", 1, 1),
    ("combat_down_first4", "hero_front_fist_thrust_20261012.png", 4, 1),
)


def components_from_alpha(alpha: Image.Image, threshold: int):
    """Label 8-connected alpha > threshold using run-length union-find."""
    width, height = alpha.size
    binary = alpha.point([int(value > threshold) for value in range(256)]).tobytes()
    parents: list[int] = []
    runs: list[tuple[int, int, int, int]] = []

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first, second = find(first), find(second)
        if first != second:
            parents[max(first, second)] = min(first, second)

    previous = []
    for y in range(height):
        row = binary[y * width:(y + 1) * width]
        current = []
        cursor = 0
        previous_cursor = 0
        while cursor < width:
            x0 = row.find(b"\x01", cursor)
            if x0 < 0:
                break
            x1 = row.find(b"\x00", x0)
            if x1 < 0:
                x1 = width
            index = len(parents)
            parents.append(index)
            runs.append((y, x0, x1, index))
            current.append((x0, x1, index))
            # Exclusive-end x1 equality includes diagonal adjacency.
            while previous_cursor < len(previous) and previous[previous_cursor][1] < x0:
                previous_cursor += 1
            nearby = previous_cursor
            while nearby < len(previous) and previous[nearby][0] <= x1:
                union(index, previous[nearby][2])
                nearby += 1
            cursor = x1
        previous = current

    groups: dict[int, dict] = {}
    root_runs = []
    for y, x0, x1, index in runs:
        root = find(index)
        root_runs.append((y, x0, x1, root))
        group = groups.setdefault(root, {"root": root, "pixels": 0,
                                         "bounds": [width, height, 0, 0]})
        group["pixels"] += x1 - x0
        bounds = group["bounds"]
        bounds[0], bounds[1] = min(bounds[0], x0), min(bounds[1], y)
        bounds[2], bounds[3] = max(bounds[2], x1), max(bounds[3], y + 1)
    ordered = sorted(groups.values(), key=lambda item: (-item["pixels"], item["bounds"]))
    for component_id, group in enumerate(ordered):
        group["id"] = component_id
        x0, y0, x1, y1 = group["bounds"]
        group["bbox_xywh"] = [x0, y0, x1 - x0, y1 - y0]
    return ordered, root_runs


def foreign_pixels(bounds, own_roots, runs, by_root):
    x0, y0, x1, y1 = bounds
    found = defaultdict(int)
    for y, start, end, root in runs:
        if y0 <= y < y1 and root not in own_roots:
            overlap = min(end, x1) - max(start, x0)
            if overlap > 0:
                found[by_root[root]["id"]] += overlap
    by_id = {group["id"]: group for group in by_root.values()}
    return [{"component_id": key, "pixels": value,
             "component_total_pixels": by_id[key]["pixels"]}
            for key, value in sorted(found.items())]


def analyze(path: Path, key: str, columns: int, rows: int,
            threshold: int = 127, min_subject_pixels: int = 1000):
    with Image.open(path) as image:
        image.load()
        width, height = image.size
        mode = image.mode
        alpha = image.getchannel("A") if "A" in image.getbands() else Image.new("L", image.size, 255)
        histogram = alpha.histogram()
        groups, runs = components_from_alpha(alpha, threshold)
    by_root = {group["root"]: group for group in groups}
    large = [group for group in groups if group["pixels"] >= min_subject_pixels]
    slots = []
    for index in range(columns * rows):
        column, row = index % columns, index // columns
        # Grid only locates expected subjects. It does not constrain regions.
        expected = [column * width // columns, row * height // rows,
                    (column + 1) * width // columns, (row + 1) * height // rows]
        candidates = []
        for group in large:
            x0, y0, x1, y1 = group["bounds"]
            center_x, center_y = (x0 + x1) / 2, (y0 + y1) / 2
            if expected[0] <= center_x < expected[2] and expected[1] <= center_y < expected[3]:
                candidates.append(group)
        candidates.sort(key=lambda group: -group["pixels"])
        slot = {"index": index, "expected_grid_bounds_exclusive": expected,
                "candidate_component_ids": [group["id"] for group in candidates]}
        if len(candidates) == 1:
            subject = candidates[0]
            bounds = subject["bounds"]
            foreign = foreign_pixels(bounds, {subject["root"]}, runs, by_root)
            foreign_subjects = [item for item in foreign if item["component_total_pixels"] >= min_subject_pixels]
            padding_checks = []
            for padding in (0, 1, 2, 4, 8):
                padded = [max(0, bounds[0] - padding), max(0, bounds[1] - padding),
                          min(width, bounds[2] + padding), min(height, bounds[3] + padding)]
                padded_foreign = foreign_pixels(padded, {subject["root"]}, runs, by_root)
                foreign_count = sum(item["pixels"] for item in padded_foreign)
                padding_checks.append({"padding": padding,
                                       "region_xywh": [padded[0], padded[1],
                                                       padded[2] - padded[0], padded[3] - padded[1]],
                                       "foreign_alpha_gt_threshold_pixels": foreign_count})
            # Prefer two pixels of original soft edge without another foreground
            # component. Fall back to one or zero; never cut the own component.
            recommended = next((check for padding in (2, 1, 0)
                                for check in padding_checks
                                if check["padding"] == padding
                                and check["foreign_alpha_gt_threshold_pixels"] == 0), None)
            slot.update({"subject_component_id": subject["id"],
                         "subject_pixels": subject["pixels"],
                         "region_xywh": subject["bbox_xywh"],
                         "bounds_exclusive": bounds,
                         "foreign_alpha_gt_threshold_pixels": sum(item["pixels"] for item in foreign),
                         "foreign_components": foreign,
                         "foreign_subject_pixels": sum(item["pixels"] for item in foreign_subjects),
                         "rectangular_subject_isolation": not foreign_subjects,
                         "recommended_gpu_region_xywh": recommended["region_xywh"] if recommended else None,
                         "recommended_padding": recommended["padding"] if recommended else None,
                         "padding_checks": padding_checks,
                         "clips_own_subject_pixels": 0,
                         "touches_canvas_edge": bounds[0] == 0 or bounds[1] == 0 or bounds[2] == width or bounds[3] == height,
                         "review_note": "Check detached small components, pose semantics and soft-alpha edges visually; not a visual PASS."})
        else:
            slot["rectangular_subject_isolation"] = False
            slot["review_note"] = "Ambiguous/missing connected subject; manual review required."
        slots.append(slot)
    return {"key": key, "path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "size": [width, height], "mode": mode,
            "expected_layout": [columns, rows], "alpha_gt_threshold": threshold,
            "alpha_histogram_summary": {"zero": histogram[0], "partial": sum(histogram[1:255]),
                                        "opaque": histogram[255],
                                        "foreground_gt_threshold": sum(histogram[threshold + 1:])},
            "min_subject_component_pixels": min_subject_pixels,
            "component_count": len(groups), "large_component_count": len(large),
            "components": [{key: value for key, value in group.items() if key != "root"} for group in groups],
            "slots": slots}


def self_test():
    """Synthetic diagonal connectivity, foreign overlap and transparent RGB."""
    alpha = Image.new("L", (7, 6), 0)
    alpha.putpixel((0, 0), 128)
    alpha.putpixel((1, 1), 254)
    alpha.putpixel((2, 0), 127)
    alpha.putpixel((3, 2), 255)
    alpha.putpixel((3, 3), 255)
    groups, runs = components_from_alpha(alpha, 127)
    assert sorted(group["pixels"] for group in groups) == [2, 2]
    assert any(group["bounds"] == [0, 0, 2, 2] for group in groups)
    own = next(group for group in groups if group["bounds"] == [0, 0, 2, 2])
    foreign = foreign_pixels([0, 0, 4, 4], {own["root"]}, runs,
                             {group["root"]: group for group in groups})
    assert sum(item["pixels"] for item in foreign) == 2
    rgba = Image.new("RGBA", (2, 2), (255, 250, 0, 0))
    empty, _ = components_from_alpha(rgba.getchannel("A"), 127)
    assert empty == []
    # Independent exhaustive flood-fill checks the run-length implementation.
    rng = random.Random(20261012)
    for _ in range(20):
        size = 13
        points = {(x, y) for y in range(size) for x in range(size) if rng.random() < 0.25}
        test_alpha = Image.new("L", (size, size), 0)
        for point in points:
            test_alpha.putpixel(point, 255)
        pending = set(points)
        expected = []
        while pending:
            seed = pending.pop()
            component = {seed}
            stack = [seed]
            while stack:
                x, y = stack.pop()
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        neighbor = (x + dx, y + dy)
                        if neighbor in pending:
                            pending.remove(neighbor)
                            component.add(neighbor)
                            stack.append(neighbor)
            xs, ys = zip(*component)
            expected.append((len(component), [min(xs), min(ys), max(xs) + 1, max(ys) + 1]))
        actual, _ = components_from_alpha(test_alpha, 127)
        assert sorted(expected) == sorted((group["pixels"], group["bounds"]) for group in actual)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--threshold", type=int, default=127)
    parser.add_argument("--min-subject-pixels", type=int, default=1000)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--source", nargs=4, action="append", metavar=("KEY", "PATH", "COLS", "ROWS"),
                        help="Measure only these sources (repeatable); emits incremental JSON to stdout. PATH is absolute or project-relative.")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("REGION_ANALYZER_SELF_TEST_PASS")
        return
    if not 0 <= args.threshold < 255:
        parser.error("threshold must be in [0, 254]")
    if args.min_subject_pixels < 1:
        parser.error("min-subject-pixels must be positive")
    directory = args.root.resolve() / "docs" / "art_reference"
    sources = []
    if args.source:
        for key, path_text, columns_text, rows_text in args.source:
            try:
                columns, rows = int(columns_text), int(rows_text)
            except ValueError:
                parser.error("source COLS and ROWS must be integers")
            if not key or columns < 1 or rows < 1:
                parser.error("source KEY must be nonempty and COLS/ROWS must be positive")
            path = Path(path_text)
            if not path.is_absolute():
                path = args.root.resolve() / path
            sources.append((path, key, columns, rows))
        if len({key for _, key, _, _ in sources}) != len(sources):
            parser.error("source KEY values must be unique")
    else:
        sources = [(directory / filename, key, columns, rows)
                   for key, filename, columns, rows in SOURCES]
    result = {"schema": 1, "read_only": True, "connectivity": 8,
              "alpha_threshold_comparison": ">", "threshold": args.threshold,
              "images": [analyze(path, key, columns, rows, args.threshold,
                                 args.min_subject_pixels)
                         for path, key, columns, rows in sources]}
    # Compact output avoids tool stdout truncation for the complete inventory.
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
