#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"
python3 tools/validate_repo.py
python3 tools/run_checked.py import ./tools/godot.sh --headless --path "$task_root" --editor --import
python3 tools/run_checked.py state_services ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_state_services.gd
python3 tools/run_checked.py project_contract ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_project_contract.gd
python3 tools/run_checked.py ui_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_ui_flow.gd
python3 tools/run_checked.py main_smoke ./tools/godot.sh --headless --path "$task_root" -- --smoke-test
echo "PROJECT_CHECK_PASS"
