#!/usr/bin/env python3
"""Validate Markdown local paths, structured content, and resource paths."""
import csv
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
errors = []
documents = (list(root.glob("*.md")) + list((root / "docs").glob("*.md"))
             + list((root / "docs" / "reviews").rglob("*.md")))
for doc in documents:
    text = doc.read_text()
    if len(re.findall(r"^\s*```", text, re.M)) % 2:
        errors.append(f"{doc.name}: unclosed fence")
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if re.match(r"(https?://|mailto:|#)", target):
            continue
        target = target.split("#", 1)[0]
        if target and not (doc.parent / target).exists():
            errors.append(f"{doc.name}: broken link {target}")
for path in (root / "game" / "content").rglob("*.json"):
    try:
        json.loads(path.read_text())
    except (ValueError, OSError) as error:
        errors.append(f"{path.name}: {error}")
for path in (root / "game" / "content").rglob("*.csv"):
    with path.open(newline="") as stream:
        rows = list(csv.reader(stream))
    if not rows or rows[0][0] != "keys":
        errors.append(f"{path.name}: missing keys header")
    elif len({row[0] for row in rows[1:]}) != len(rows) - 1 or any(len(row) != len(rows[0]) for row in rows):
        errors.append(f"{path.name}: duplicate key or unequal columns")
for path in [root / "project.godot", *list((root / "game").rglob("*.tscn"))]:
    for target in re.findall(r'res://([^"]+)', path.read_text()):
        if not (root / target).exists():
            errors.append(f"{path.name}: missing resource {target}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"REPO_VALIDATION_PASS documents={len(documents)}")
