#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"
python3 tools/validate_repo.py
python3 -B -m unittest discover -s tools/tests -p 'test_hero_manifest.py'
python3 -B -m unittest discover -s tools/tests -p 'test_review_bundle.py'
python3 tools/run_checked.py import ./tools/godot.sh --headless --path "$task_root" --editor --import
python3 tools/run_checked.py character_source ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_character_source.gd
python3 tools/run_checked.py character_pipeline ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_character_pipeline.gd
python3 tools/run_checked.py character_manifest_renderer ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_character_manifest_renderer.gd
python3 tools/build_hero_imagegen_manifest.py --verify
python3 tools/run_checked.py character_imagegen_pipeline ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_character_imagegen_pipeline.gd
python3 tools/run_checked.py state_services ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_state_services.gd
python3 tools/run_checked.py project_contract ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_project_contract.gd
python3 tools/run_checked.py ui_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_ui_flow.gd
python3 tools/run_checked.py save_slots_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_save_slots_ui.gd
python3 tools/run_checked.py exploration_controller ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_controller.gd
python3 tools/run_checked.py exploration_content ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_content.gd
python3 tools/run_checked.py exploration_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_flow.gd
python3 tools/run_checked.py exploration_walk ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_exploration_walk.gd
python3 tools/run_checked.py battle_foundation ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_battle_foundation.gd
python3 tools/run_checked.py combat_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_combat_rules.gd
python3 tools/run_checked.py combat_edges ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_combat_edges.gd
python3 tools/run_checked.py combat_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_combat_ui.gd
python3 tools/run_checked.py skill_preview ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_battle_skill_preview.gd
python3 tools/run_checked.py command_options ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_battle_command_options.gd
python3 tools/run_checked.py investigation_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_investigation_rules.gd
python3 tools/run_checked.py dialogue ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_dialogue.gd
python3 tools/run_checked.py inquiry ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_inquiry.gd
python3 tools/run_checked.py onboarding ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_onboarding.gd
python3 tools/run_checked.py week4_feedback ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week4_feedback.gd
python3 tools/run_checked.py handover ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_handover.gd
python3 tools/run_checked.py story_encounter ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_story_encounter.gd
python3 tools/check_story_persistence.py
python3 tools/run_checked.py main_smoke ./tools/godot.sh --headless --path "$task_root" -- --smoke-test
echo "PROJECT_CHECK_PASS"
