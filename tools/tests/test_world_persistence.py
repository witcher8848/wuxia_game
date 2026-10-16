"""Protocol/orchestration unit tests only; fake runners are not runtime evidence."""
from __future__ import annotations

import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "world_persistence_checker", Path(__file__).resolve().parents[1] / "check_world_persistence.py")
assert SPEC is not None and SPEC.loader is not None
checker = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = checker
SPEC.loader.exec_module(checker)

FIXTURE = "user://tests/world_session_unit_123"


def marker(phase="write", pid=701, checks=17, packed="false", fixture=FIXTURE):
    return (f"WEEK7_WORLD_SESSION_PHASE_PASS phase={phase} pid={pid} checks={checks} "
            f"packed={packed} fixture={fixture}\n")


class WorldPersistenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="world_persistence_unit_")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.output = io.StringIO()
        self.calls = []

    def run_with(self, results, fixture=FIXTURE):
        def fake_runner(command, **kwargs):
            self.calls.append((command, kwargs))
            # Reader may not launch until writer returned, passed exact marker,
            # was logged, and emitted its post-exit receipt.
            if len(self.calls) == 2:
                self.assertIn("WORLD_PERSISTENCE_PHASE_EXITED phase=write pid=701 returncode=0",
                              self.output.getvalue())
                self.assertTrue((self.root / "builds/qa/week7_world_persistence_write.log").is_file())
            result = results[len(self.calls)-1]
            if isinstance(result, Exception):
                raise result
            return subprocess.CompletedProcess(command, result[0], result[1])
        return checker.run_world_persistence(self.root, fixture=fixture,
                                             runner=fake_runner, output=self.output)

    def test_success_sequential_source_only_same_isolated_fixture_and_real_logs(self):
        self.assertEqual(self.run_with([(0, marker()), (0, marker("read", 702, 9999))]), 0)
        self.assertEqual(len(self.calls), 2)
        for index, (command, kwargs) in enumerate(self.calls):
            self.assertEqual(command, [str(self.root / "tools/godot.sh"), "--headless", "--path", str(self.root),
                                      "--script", str(self.root / "game/tests/test_week7_world_session.gd"), "--",
                                      f"--fixture={FIXTURE}", f"--phase={('write','read')[index]}"])
            self.assertEqual(kwargs["timeout"], 60)
            self.assertEqual(kwargs["cwd"], self.root)
            self.assertIs(kwargs["stdout"], subprocess.PIPE)
            self.assertIs(kwargs["stderr"], subprocess.STDOUT)
            self.assertIs(kwargs["text"], True)
        self.assertIn("writer_pid=701 reader_pid=702 packed=false (writer exited before reader launched)", self.output.getvalue())
        self.assertEqual((self.root / "builds/qa/week7_world_persistence_read.log").read_text(), marker("read",702,9999))

    def test_positive_check_counts_are_dynamic_not_hardcoded(self):
        self.assertEqual(checker.phase_pid(marker(checks=1), "write", FIXTURE), 701)
        self.assertEqual(checker.phase_pid(marker(checks=1000000), "write", FIXTURE), 701)

    def test_invalid_markers_rejected_without_starting_reader(self):
        for text in ["", marker()+marker(), marker("read"), marker(pid=0), marker(pid=-1),
                     marker(checks=0), marker(checks=-1), marker(packed="true"),
                     marker(fixture=FIXTURE+"_other"), "prefix "+marker(), marker().rstrip()+" trailing\n",
                     marker()+"WEEK7_WORLD_SESSION_PHASE_PASS malformed\n"]:
            with self.subTest(text=text):
                self.calls.clear()
                self.output = io.StringIO()
                self.assertEqual(self.run_with([(0,text)]), 1)
                self.assertEqual(len(self.calls), 1)
                self.assertNotIn("WORLD_PERSISTENCE_RESTART_PASS",self.output.getvalue())

    def test_process_error_or_godot_error_with_exit_zero_prevents_reader(self):
        for code, text in [(4,marker()),(-15,marker()),(0,marker()+"SCRIPT ERROR: invalid\n"),
                           (0,marker()+"ERROR: invalid\n"),(0,marker()+"Parse Error: invalid\n"),
                           (0,marker()+"WEEK7_WORLD_SESSION_FAIL semantic loss\n")]:
            with self.subTest(code=code,text=text):
                self.calls.clear()
                self.output = io.StringIO()
                self.assertNotEqual(self.run_with([(code,text)]), 0)
                self.assertEqual(len(self.calls), 1)

    def test_invalid_reader_marker_cannot_claim_cold_pass(self):
        self.assertEqual(self.run_with([(0,marker()),(0,marker("read",702,packed="true"))]),1)
        self.assertNotIn("WORLD_PERSISTENCE_RESTART_PASS",self.output.getvalue())

    def test_reused_process_identity_rejected(self):
        self.assertEqual(self.run_with([(0,marker()),(0,marker("read",701))]),1)
        self.assertIn("identities reused",self.output.getvalue())
        self.assertNotIn("WORLD_PERSISTENCE_RESTART_PASS",self.output.getvalue())

    def test_timeout_preserves_byte_output_and_never_launches_reader(self):
        error = subprocess.TimeoutExpired(["fixture"],60,output=b"partial\xff")
        self.assertEqual(self.run_with([error]),124)
        self.assertEqual(len(self.calls),1)
        saved = (self.root / "builds/qa/week7_world_persistence_write.log").read_text()
        self.assertIn("partial",saved)
        self.assertIn("WORLD_PERSISTENCE_TIMEOUT phase=write",saved)
        self.assertNotIn("WORLD_PERSISTENCE_RESTART_PASS",self.output.getvalue())

    def test_read_timeout_is_not_retried(self):
        error = subprocess.TimeoutExpired(["fixture"],60,output="reader partial")
        self.assertEqual(self.run_with([(0,marker()),error]),124)
        self.assertEqual(len(self.calls),2)
        self.assertIn("reader partial",(self.root / "builds/qa/week7_world_persistence_read.log").read_text())

    def test_launch_error_is_logged_and_stops(self):
        self.assertEqual(self.run_with([OSError("missing executable")]),127)
        self.assertEqual(len(self.calls),1)
        self.assertIn("missing executable",(self.root / "builds/qa/week7_world_persistence_write.log").read_text())

    def test_invalid_or_broad_fixture_never_launches_a_process(self):
        for fixture in ["user://", "user://tests/other", "user://tests/world_session_a/../b",
                        "user://tests/world_session_", "user://tests/world_session_"+"x"*96]:
            with self.subTest(fixture=fixture):
                self.calls.clear()
                self.assertEqual(self.run_with([],fixture),1)
                self.assertEqual(self.calls,[])


if __name__ == "__main__":
    unittest.main()
