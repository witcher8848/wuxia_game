"""Strict fake-runner protocol tests only; these are not runtime/save evidence."""
from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "branch_persistence_checker", Path(__file__).resolve().parents[1] / "check_branch_persistence.py")
assert SPEC is not None and SPEC.loader is not None
checker = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = checker
SPEC.loader.exec_module(checker)

FIXTURE = "user://tests/branch_session_unit_123"
ORDER = (("home", "write"), ("home", "read"), ("dock", "write"), ("dock", "read"))


def marker(phase="write", choice="home", pid=701, checks=17, packed="false", fixture=None):
    fixture = f"{FIXTURE}_{choice}" if fixture is None else fixture
    return (f"BRANCH_CHOICE_SESSION_PHASE_PASS phase={phase} choice={choice} pid={pid} checks={checks} "
            f"packed={packed} fixture={fixture}\n")


def successful_results():
    return [(0, marker(phase, choice, 701 + index, 1 + index))
            for index, (choice, phase) in enumerate(ORDER)]


class BranchPersistenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="branch_persistence_unit_")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.output = io.StringIO()
        self.calls = []

    def reset_observations(self):
        self.output = io.StringIO()
        self.calls.clear()

    def run_with(self, results, fixture=FIXTURE):
        def fake_runner(command, **kwargs):
            index = len(self.calls)
            self.calls.append((command, kwargs))
            # The next child cannot launch before the previous call returned,
            # its exact marker passed, its log exists, and its exit was noted.
            if index:
                previous_choice, previous_phase = ORDER[index - 1]
                self.assertIn(
                    f"BRANCH_PERSISTENCE_PHASE_EXITED choice={previous_choice} phase={previous_phase}",
                    self.output.getvalue())
                self.assertTrue((self.root / f"builds/qa/week8_branch_{previous_choice}_{previous_phase}.log").is_file())
            result = results[index]
            if isinstance(result, Exception):
                raise result
            return subprocess.CompletedProcess(command, result[0], result[1])
        return checker.run_branch_persistence(self.root, fixture=fixture,
                                             runner=fake_runner, output=self.output)

    def test_four_sequential_source_processes_distinct_route_fixtures_and_exact_logs(self):
        results = successful_results()
        self.assertEqual(self.run_with(results), 0)
        self.assertEqual(len(self.calls), 4)
        for index, (command, kwargs) in enumerate(self.calls):
            choice, phase = ORDER[index]
            self.assertEqual(command, [str(self.root / "tools/godot.sh"), "--headless", "--path", str(self.root),
                                      "--script", str(self.root / "game/tests/test_branch_choice_session.gd"), "--",
                                      f"--fixture={FIXTURE}_{choice}", f"--phase={phase}", f"--choice={choice}"])
            self.assertEqual(kwargs["timeout"], 60)
            self.assertEqual(kwargs["cwd"], self.root)
            self.assertIs(kwargs["stdout"], subprocess.PIPE)
            self.assertIs(kwargs["stderr"], subprocess.STDOUT)
            self.assertIs(kwargs["text"], True)
            self.assertEqual((self.root / f"builds/qa/week8_branch_{choice}_{phase}.log").read_text(), results[index][1])
        for choice, writer, reader in (("home", 701, 702), ("dock", 703, 704)):
            self.assertIn(f"writer_pid={writer} reader_pid={reader} packed=false (writer exited before reader launched)",
                          self.output.getvalue())
        self.assertIn("BRANCH_PERSISTENCE_RESTART_PASS choices=home,dock processes=4 packed=false", self.output.getvalue())

    def test_check_count_is_positive_and_dynamic_not_hardcoded(self):
        for checks in (1, 1000000):
            self.assertEqual(checker.phase_pid(marker(checks=checks), "write", "home", f"{FIXTURE}_home"), 701)

    def test_invalid_writer_markers_stop_before_reader(self):
        for text in ["", marker() + marker(), marker("read"), marker(choice="dock"), marker(pid=0),
                     marker(pid=-1), marker(checks=0), marker(checks=-1), marker(packed="true"),
                     marker(fixture=FIXTURE + "_other"), "prefix " + marker(), marker().rstrip() + " trailing\n",
                     marker() + "BRANCH_CHOICE_SESSION_PHASE_PASS malformed\n",
                     marker(pid="01"), marker(checks="+1"), marker().replace("phase=write", "phase=write ")]:
            with self.subTest(text=text):
                self.reset_observations()
                self.assertEqual(self.run_with([(0, text)]), 1)
                self.assertEqual(len(self.calls), 1)
                self.assertNotIn("BRANCH_PERSISTENCE_RESTART_PASS", self.output.getvalue())

    def test_unknown_protocol_phase_or_choice_is_rejected(self):
        for phase, choice in (("other", "home"), ("write", "other"), ("", "dock")):
            with self.subTest(phase=phase, choice=choice), self.assertRaises(ValueError):
                checker.phase_pid(marker(), phase, choice, f"{FIXTURE}_home")

    def test_process_or_error_output_even_with_pass_stops(self):
        for code, text in [(4, marker()), (-15, marker()), (0, marker() + "SCRIPT ERROR: invalid\n"),
                           (0, marker() + "ERROR: invalid\n"), (0, marker() + "Parse Error: invalid\n"),
                           (0, marker() + "BRANCH_CHOICE_SESSION_FAIL semantic loss\n"),
                           (0, marker() + "BRANCH_CHOICE_SESSION_PHASE_FAIL write\n")]:
            with self.subTest(code=code, text=text):
                self.reset_observations()
                self.assertNotEqual(self.run_with([(code, text)]), 0)
                self.assertEqual(len(self.calls), 1)

    def test_each_phase_is_checked_and_failure_stops_remaining_launches(self):
        for failing_index in range(1, 4):
            with self.subTest(failing_index=failing_index):
                self.reset_observations()
                results = successful_results()
                results[failing_index] = (0, results[failing_index][1].replace("packed=false", "packed=true"))
                self.assertEqual(self.run_with(results), 1)
                self.assertEqual(len(self.calls), failing_index + 1)
                self.assertNotIn("BRANCH_PERSISTENCE_RESTART_PASS", self.output.getvalue())

    def test_reused_pid_within_or_between_routes_is_rejected(self):
        for duplicate_index in (1, 2, 3):
            with self.subTest(duplicate_index=duplicate_index):
                self.reset_observations()
                results = successful_results()
                choice, phase = ORDER[duplicate_index]
                results[duplicate_index] = (0, marker(phase, choice, 701))
                self.assertEqual(self.run_with(results), 1)
                self.assertEqual(len(self.calls), duplicate_index + 1)
                self.assertIn("identities reused", self.output.getvalue())
                self.assertNotIn("BRANCH_PERSISTENCE_RESTART_PASS", self.output.getvalue())

    def test_timeout_preserves_byte_output_and_does_not_retry_or_launch_reader(self):
        self.assertEqual(self.run_with([subprocess.TimeoutExpired(["fixture"], 60, output=b"partial\xff")]), 124)
        self.assertEqual(len(self.calls), 1)
        saved = (self.root / "builds/qa/week8_branch_home_write.log").read_text()
        self.assertIn("partial", saved)
        self.assertIn("BRANCH_PERSISTENCE_TIMEOUT choice=home phase=write", saved)
        self.assertNotIn("BRANCH_PERSISTENCE_RESTART_PASS", self.output.getvalue())

    def test_timeout_in_each_later_phase_stops_without_retry(self):
        for index in range(1, 4):
            with self.subTest(index=index):
                self.reset_observations()
                results = successful_results()
                results[index] = subprocess.TimeoutExpired(["fixture"], 60, output="phase partial")
                self.assertEqual(self.run_with(results), 124)
                self.assertEqual(len(self.calls), index + 1)
                choice, phase = ORDER[index]
                self.assertIn("phase partial", (self.root / f"builds/qa/week8_branch_{choice}_{phase}.log").read_text())

    def test_empty_timeout_output_is_logged(self):
        self.assertEqual(self.run_with([subprocess.TimeoutExpired(["fixture"], 60)]), 124)
        self.assertIn("process terminated after 60 seconds", self.output.getvalue())

    def test_launch_error_is_logged_and_stops(self):
        self.assertEqual(self.run_with([OSError("missing executable")]), 127)
        self.assertEqual(len(self.calls), 1)
        self.assertIn("missing executable", (self.root / "builds/qa/week8_branch_home_write.log").read_text())

    def test_invalid_broad_or_oversized_fixture_never_starts_process(self):
        for fixture in ["user://", "user://tests/other", "user://tests/branch_session_a/../b",
                        "user://tests/branch_session_", "user://tests/branch_session_" + "x" * 96,
                        "user://tests/branch_session_a.b", "/tmp/branch_session_unit",
                        "user://tests/branch_session_" + "x" * (96 - len("branch_session_") - 4)]:
            with self.subTest(fixture=fixture):
                self.reset_observations()
                self.assertEqual(self.run_with([], fixture), 1)
                self.assertEqual(self.calls, [])

    def test_log_directory_failure_does_not_launch_process(self):
        (self.root / "builds").write_text("not a directory")
        self.assertEqual(self.run_with([]), 1)
        self.assertEqual(self.calls, [])
        self.assertIn("cannot create log directory", self.output.getvalue())

    def test_pack_option_is_explicitly_unsupported(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            checker.main(["--pack", "not-a-real-pack.pck"])
        self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
