#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"
task_mode="${1:-debug}"
case "$task_mode" in debug) task_preset="Windows Debug";; release) task_preset="Windows Release";; *) exit 2;; esac
./tools/check_project.sh
task_sha="$(git rev-parse --short HEAD)"
task_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
task_version="$(python3 tools/package_metadata.py --version)"
task_out="$task_root/builds/windows/${task_version}_${task_sha}_${task_mode}_${task_stamp}"
mkdir -p "$task_out/licenses"
python3 tools/run_checked.py "export_$task_mode" ./tools/godot.sh --headless --path "$task_root" "--export-$task_mode" "$task_preset" "$task_out/ProjectWuming.exe"
python3 tools/run_checked.py "pack_$task_mode" ./tools/godot.sh --headless --path "$task_out" --main-pack "$task_out/ProjectWuming.pck" --script "$task_root/tools/audit_pack.gd"
cp licenses/GODOT.txt "$task_out/licenses/GODOT.txt"
cp licenses/GODOT-COPYRIGHT.txt "$task_out/licenses/GODOT-COPYRIGHT.txt"
if [[ -f licenses/NOTO-OFL.txt ]]; then cp licenses/NOTO-OFL.txt "$task_out/licenses/NOTO-OFL.txt"; fi
cp docs/windows_quickstart.txt "$task_out/README.txt"
python3 tools/package_metadata.py "$task_out" "$task_mode"
echo "WINDOWS_BUILD_PASS $task_out"
