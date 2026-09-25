#!/bin/bash
set -e
cd "$(dirname "$0")"
./tools/godot.sh --headless --path . --editor --import
exec ./tools/godot.sh --path . res://game/tools/battle_lab/battle_lab.tscn -- --dev
