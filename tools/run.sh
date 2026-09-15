#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$task_root/tools/godot.sh" --headless --path "$task_root" --editor --import
exec "$task_root/tools/godot.sh" --path "$task_root" -- "$@"
