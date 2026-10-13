#!/bin/bash
set -e
cd "$(dirname "$0")"
./tools/godot.sh --headless --path . --editor --import
exec ./tools/godot.sh --path . res://game/presentation/battle/combat_v1_trial.tscn
