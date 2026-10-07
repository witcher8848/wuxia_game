#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./tools/godot.sh --headless --path "$PWD" --editor --import
exec ./tools/godot.sh --path "$PWD" res://game/presentation/characters/character_lab.tscn
