import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROBE_PATH = Path(__file__).parents[1] / "spikes" / "provider-state" / "probe.py"
SPEC = importlib.util.spec_from_file_location("provider_state_probe", PROBE_PATH)
assert SPEC and SPEC.loader
probe = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = probe
SPEC.loader.exec_module(probe)


class ProbeFixtureTest(unittest.TestCase):
    def jsonl(self, *records):
        temporary = tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False)
        self.addCleanup(Path(temporary.name).unlink, missing_ok=True)
        with temporary:
            for record in records:
                temporary.write(json.dumps(record) + "\n")
        return Path(temporary.name)

    @staticmethod
    def codex(event_type, **payload):
        return {
            "timestamp": "2026-07-14T00:00:00Z",
            "type": "event_msg",
            "payload": {"type": event_type, **payload},
        }

    @staticmethod
    def claude(entry_type, content):
        return {
            "timestamp": "2026-07-14T00:00:00Z",
            "type": entry_type,
            "sessionId": "fixture-session",
            "cwd": "/private/tmp/fixture",
            "message": {"content": content},
        }

    def test_codex_real_input_wait_and_resume(self):
        path = self.jsonl(
            self.codex("task_started"),
            self.codex("function_call", name="request_user_input", call_id="input-1"),
        )
        self.assertEqual(
            probe.codex_rollout_status(path, False)["activeFlags"],
            ["waitingOnUserInput"],
        )

        path = self.jsonl(
            self.codex("task_started"),
            self.codex("function_call", name="request_user_input", call_id="input-1"),
            self.codex("function_call_output", call_id="input-1"),
            self.codex("task_complete"),
        )
        self.assertEqual(probe.codex_rollout_status(path, False)["type"], "idle")

    def test_codex_abort_clears_active_work_and_waits(self):
        path = self.jsonl(
            self.codex("task_started"),
            self.codex("function_call", name="request_user_input", call_id="input-1"),
            self.codex("turn_aborted"),
        )
        self.assertEqual(probe.codex_rollout_status(path, False)["type"], "idle")

    def test_claude_real_question_wait_and_resume(self):
        question = {"type": "tool_use", "name": "AskUserQuestion", "id": "question-1"}
        path = self.jsonl(self.claude("user", "start"), self.claude("assistant", [question]))
        self.assertEqual(probe.claude_desktop_session(path, set())["state"], "waiting_for_input")

        result = {"type": "tool_result", "tool_use_id": "question-1"}
        path = self.jsonl(
            self.claude("user", "start"),
            self.claude("assistant", [question]),
            self.claude("user", [result]),
            self.claude("assistant", [{"type": "text", "text": "complete"}]),
        )
        self.assertEqual(probe.claude_desktop_session(path, set())["state"], "idle")

    def test_claude_exact_interrupt_marker_clears_question(self):
        question = {"type": "tool_use", "name": "AskUserQuestion", "id": "question-1"}
        interrupted = {"type": "text", "text": "[Request interrupted by user]"}
        path = self.jsonl(
            self.claude("user", "start"),
            self.claude("assistant", [question]),
            self.claude("user", [interrupted]),
        )
        self.assertEqual(probe.claude_desktop_session(path, set())["state"], "idle")

    def test_prompt_like_assistant_text_is_not_a_wait(self):
        phrases = "Should I proceed? Permission required. Waiting for your approval."
        path = self.jsonl(
            self.claude("user", "start"),
            self.claude("assistant", [{"type": "text", "text": phrases}]),
        )
        self.assertEqual(probe.claude_desktop_session(path, set())["state"], "idle")


if __name__ == "__main__":
    unittest.main()
