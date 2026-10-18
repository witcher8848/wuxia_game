#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"
python3 tools/validate_repo.py
python3 -B -m unittest discover -s tools/tests -p 'test_hero_manifest.py'
python3 -B -m unittest discover -s tools/tests -p 'test_review_bundle.py'
python3 -B -m unittest discover -s tools/tests -p 'test_week6_candidate.py'
python3 -B -m unittest discover -s tools/tests -p 'test_week6_feedback_candidate.py'
python3 -B -m unittest discover -s tools/tests -p 'test_world_persistence.py'
python3 -B -m unittest discover -s tools/tests -p 'test_branch_persistence.py'
python3 -B -m unittest discover -s tools/tests -p 'test_week8_candidate.py'
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
python3 tools/run_checked.py martial_loadout ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_martial_loadout.gd
python3 tools/run_checked.py week6_ai ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_ai.gd
python3 tools/run_checked.py week6_preview ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_battle_preview.gd
python3 tools/run_checked.py week6_preparation ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_preparation.gd
python3 tools/run_checked.py week6_martial_session ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_martial_session.gd
python3 tools/run_checked.py week6_trial ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_trial.gd
python3 tools/run_checked.py battle_tactics ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_battle_tactics.gd
python3 tools/run_checked.py board_visibility ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_board_visibility.gd
python3 tools/run_checked.py tactics_encounter ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_tactics_encounter.gd
python3 tools/run_checked.py week6_feedback_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_feedback_ui.gd
python3 tools/run_checked.py week6_feedback_session ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week6_feedback_session.gd
python3 tools/run_checked.py investigation_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_investigation_rules.gd
python3 tools/run_checked.py branch_choice_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_branch_choice_rules.gd
python3 tools/run_checked.py choice_anchors ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_choice_anchors.gd
python3 tools/run_checked.py branch_choice_session ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_branch_choice_session.gd
python3 tools/run_checked.py automatic_saves ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_automatic_saves.gd
python3 tools/run_checked.py week8_flow ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week8_flow.gd
python3 tools/run_checked.py week8_branch_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week8_branch_ui.gd
python3 tools/run_checked.py dialogue ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_dialogue.gd
python3 tools/run_checked.py inquiry ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_inquiry.gd
python3 tools/run_checked.py onboarding ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_onboarding.gd
python3 tools/run_checked.py week4_feedback ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week4_feedback.gd
python3 tools/run_checked.py handover ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_handover.gd
python3 tools/run_checked.py story_encounter ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_story_encounter.gd
python3 tools/run_checked.py world_rules ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_world_rules.gd
python3 tools/run_checked.py week7_content ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week7_content.gd
python3 tools/run_checked.py week7_npc_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week7_npc_ui.gd
python3 tools/run_checked.py week7_world_session ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week7_world_session.gd
python3 tools/run_checked.py week7_world_ui ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_week7_world_ui.gd
python3 tools/run_checked.py review_presentation ./tools/godot.sh --headless --path "$task_root" --script res://game/tests/test_review_presentation.gd
python3 tools/check_story_persistence.py
python3 tools/check_martial_persistence.py
python3 -B tools/check_world_persistence.py
python3 -B tools/check_branch_persistence.py
python3 -B tools/check_week8_persistence.py
python3 tools/run_checked.py main_smoke ./tools/godot.sh --headless --path "$task_root" -- --smoke-test
echo "PROJECT_CHECK_PASS"
