#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_version="$(tr -d '\r\n' < "$task_root/.godot-version")"
task_godot="${GODOT_BIN:-}"
if [[ -z "$task_godot" ]]; then
  for candidate in "$task_root/.tools/godot/Godot.app/Contents/MacOS/Godot" "$task_root/.tools/godot/godot" "$task_root/.tools/godot/godot.exe" "/Applications/Godot.app/Contents/MacOS/Godot"; do
    if [[ -x "$candidate" ]]; then task_godot="$candidate"; break; fi
  done
fi
if [[ -z "$task_godot" ]]; then
  echo "Godot $task_version missing. Run ./tools/setup_godot.sh or set GODOT_BIN." >&2
  exit 1
fi
task_actual="$("$task_godot" --version)"
case "$task_actual" in "$task_version.stable."*) ;; *) echo "Wrong Godot version: $task_actual (expected $task_version stable)" >&2; exit 1;; esac
exec "$task_godot" "$@"
