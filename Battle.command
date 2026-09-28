#!/bin/bash
set -e
cd "$(dirname "$0")"
./tools/godot.sh --headless --path . --editor --import
exec ./tools/godot.sh --path . res://game/tools/battle_lab/combat_lab.tscn -- --dev
