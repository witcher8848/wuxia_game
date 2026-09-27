#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"
python3 tools/validate_repo.py
python3 tools/run_checked.py import ./tools/godot.sh --headless --path "$task_root" --editor --import
python3 tools/run_checked.py state_services ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_state_services.gd
python3 tools/run_checked.py project_contract ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_project_contract.gd
python3 tools/run_checked.py ui_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_ui_flow.gd
python3 tools/run_checked.py save_slots_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_save_slots_ui.gd
python3 tools/run_checked.py exploration_controller ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_controller.gd
python3 tools/run_checked.py exploration_content ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_content.gd
python3 tools/run_checked.py exploration_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_flow.gd
python3 tools/run_checked.py exploration_walk ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_walk.gd
python3 tools/run_checked.py battle_foundation ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_battle_foundation.gd
python3 tools/run_checked.py investigation_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_investigation_rules.gd
python3 tools/run_checked.py main_smoke ./tools/godot.sh --headless --path "$task_root" -- --smoke-test
echo "PROJECT_CHECK_PASS"
