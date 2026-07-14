#!/usr/bin/env python3
"""Disposable, metadata-only provider state probe for Perch's viability spike."""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


CLAUDE = Path("/opt/homebrew/bin/claude")
CLAUDE_PROJECTS = Path.home() / ".claude" / "projects"
CLAUDE_DESKTOP_LOG = Path.home() / "Library" / "Logs" / "Claude" / "main.log"
CLAUDE_DESKTOP_SESSIONS = (
    Path.home() / "Library" / "Application Support" / "Claude" / "claude-code-sessions"
)
CODEX = Path("/Applications/ChatGPT.app/Contents/Resources/codex")
CODEX_STATE = Path.home() / ".codex" / "state_5.sqlite"
CODEX_LOGS = Path.home() / ".codex" / "logs_2.sqlite"


@dataclass(frozen=True)
class Observation:
    provider: str
    session_id: str
    label: str
    state: str
    waiting_on: str
    confidence: str
    last_activity: str
    native_handle: str

    def row(self) -> str:
        return " | ".join(
            (
                self.provider,
                self.session_id,
                self.label,
                self.state,
                self.waiting_on,
                self.confidence,
                self.last_activity,
                self.native_handle,
            )
        )


def safe_label(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return "-"
    return Path(value).name[:80] or "-"


def safe_id(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return "-"
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    return "".join(character for character in value if character in allowed)[:80] or "-"


def safe_timestamp(value: Any) -> str:
    if isinstance(value, str):
        return value[:80] if re.fullmatch(r"[0-9T:.+Z-]+", value) else "-"
    if not isinstance(value, (int, float)):
        return "-"
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(value))
    except (OverflowError, OSError, ValueError):
        return "-"


def normalize_codex(thread: dict[str, Any]) -> Observation:
    status = thread.get("status")
    status_type = status.get("type") if isinstance(status, dict) else None
    flags = status.get("activeFlags", []) if isinstance(status, dict) else []

    if status_type == "active" and isinstance(flags, list):
        if "waitingOnApproval" in flags:
            state, waiting_on = "waiting", "approval required"
        elif "waitingOnUserInput" in flags:
            state, waiting_on = "waiting", "input required"
        elif flags:
            state, waiting_on = "unknown", "-"
        else:
            state, waiting_on = "working", "-"
        confidence = "observed"
    elif status_type == "idle":
        state, waiting_on, confidence = "idle", "-", "observed"
    elif status_type in ("notLoaded", "systemError"):
        state, waiting_on, confidence = "unknown", "-", "stale"
    else:
        state, waiting_on, confidence = "unknown", "-", "unknown"

    return Observation(
        provider="codex",
        session_id=safe_id(thread.get("id")),
        label=safe_label(thread.get("cwd")),
        state=state,
        waiting_on=waiting_on,
        confidence=confidence,
        last_activity=safe_timestamp(thread.get("updatedAt")),
        native_handle="unavailable",
    )


def normalize_claude(session: dict[str, Any]) -> Observation:
    # Claude's machine-readable roster is validated from live records during the
    # spike. Unknown shapes deliberately remain unknown rather than guessing.
    session_id = session.get("sessionId", session.get("id"))
    cwd = session.get("cwd", session.get("workingDirectory"))
    raw_state = session.get("state", session.get("status"))
    raw_state = raw_state.lower() if isinstance(raw_state, str) else None

    known_states = {
        "working": ("working", "-"),
        "running": ("working", "-"),
        "idle": ("idle", "-"),
        "completed": ("done", "-"),
        "done": ("done", "-"),
        "waiting": ("waiting", "input required"),
        "waiting_for_input": ("waiting", "input required"),
        "waiting_for_permission": ("waiting", "permission required"),
    }
    state, waiting_on = known_states.get(raw_state, ("unknown", "-"))
    confidence = "observed" if raw_state in known_states else "unknown"

    return Observation(
        provider="claude",
        session_id=safe_id(session_id),
        label=safe_label(cwd),
        state=state,
        waiting_on=waiting_on,
        confidence=confidence,
        last_activity=safe_timestamp(
            session.get("updatedAt", session.get("lastActivity"))
        ),
        native_handle="unavailable",
    )


def codex_rollout_status(path: Path, escalation_requested: bool) -> dict[str, Any]:
    """Derive state from structured event envelopes without retaining content."""
    try:
        with path.open("rb") as stream:
            stream.seek(0, os.SEEK_END)
            size = stream.tell()
            stream.seek(max(0, size - 512_000))
            if stream.tell() > 0:
                stream.readline()
            lines = stream.readlines()
    except OSError:
        return {"type": "unknown"}

    task_active = False
    outstanding_inputs: set[str] = set()
    outstanding_approvals: set[str] = set()
    outstanding_execs: set[str] = set()
    approvals_reviewer: str | None = None
    last_timestamp: str | None = None
    for raw_line in lines:
        try:
            envelope = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(envelope, dict):
            continue
        payload = envelope.get("payload")
        if not isinstance(payload, dict):
            continue
        timestamp = envelope.get("timestamp")
        if isinstance(timestamp, str):
            last_timestamp = timestamp
        event_type = payload.get("type")
        if envelope.get("type") == "turn_context":
            reviewer = payload.get("approvals_reviewer")
            if isinstance(reviewer, str):
                approvals_reviewer = reviewer
        if event_type == "task_started":
            task_active = True
        elif event_type == "task_complete":
            task_active = False
        elif event_type == "turn_aborted":
            task_active = False
            outstanding_inputs.clear()
            outstanding_approvals.clear()
            outstanding_execs.clear()
        elif event_type == "function_call" and payload.get("name") == "request_user_input":
            call_id = payload.get("call_id")
            if isinstance(call_id, str):
                outstanding_inputs.add(call_id)
        elif event_type == "function_call_output":
            call_id = payload.get("call_id")
            if isinstance(call_id, str):
                outstanding_inputs.discard(call_id)
        elif event_type == "custom_tool_call" and payload.get("name") == "exec":
            call_id = payload.get("call_id")
            if isinstance(call_id, str):
                outstanding_execs.add(call_id)
            tool_input = payload.get("input")
            if isinstance(call_id, str) and isinstance(tool_input, str):
                try:
                    tool_metadata = json.loads(tool_input)
                except json.JSONDecodeError:
                    tool_metadata = None
                if (
                    isinstance(tool_metadata, dict)
                    and tool_metadata.get("sandbox_permissions") == "require_escalated"
                ):
                    outstanding_approvals.add(call_id)
        elif event_type == "custom_tool_call_output":
            call_id = payload.get("call_id")
            if isinstance(call_id, str):
                outstanding_approvals.discard(call_id)
                outstanding_execs.discard(call_id)

    if outstanding_approvals or (
        outstanding_execs and escalation_requested and approvals_reviewer == "user"
    ):
        return {"type": "active", "activeFlags": ["waitingOnApproval"], "timestamp": last_timestamp}
    if outstanding_inputs:
        return {"type": "active", "activeFlags": ["waitingOnUserInput"], "timestamp": last_timestamp}
    if task_active:
        return {"type": "active", "activeFlags": [], "timestamp": last_timestamp}
    return {"type": "idle", "timestamp": last_timestamp}


def list_codex() -> list[dict[str, Any]]:
    logs_uri = f"file:{CODEX_LOGS}?mode=ro"
    logs_connection = sqlite3.connect(logs_uri, uri=True, timeout=1)
    try:
        escalation_threads = {
            row[0]
            for row in logs_connection.execute(
                """
                SELECT DISTINCT thread_id
                FROM logs
                WHERE ts >= CAST(strftime('%s','now') AS INTEGER) - 600
                  AND thread_id IS NOT NULL
                  AND feedback_log_body LIKE '%sandbox_permissions%require_escalated%'
                """
            ).fetchall()
            if isinstance(row[0], str)
        }
    finally:
        logs_connection.close()

    uri = f"file:{CODEX_STATE}?mode=ro"
    connection = sqlite3.connect(uri, uri=True, timeout=1)
    try:
        rows = connection.execute(
            """
            SELECT id, cwd, rollout_path, updated_at
            FROM threads
            WHERE archived = 0 AND updated_at >= CAST(strftime('%s','now') AS INTEGER) - 3600
            ORDER BY updated_at DESC
            LIMIT 50
            """
        ).fetchall()
    finally:
        connection.close()

    sessions: list[dict[str, Any]] = []
    for session_id, cwd, rollout_path, updated_at in rows:
        if not all(isinstance(value, str) for value in (session_id, cwd, rollout_path)):
            continue
        status = codex_rollout_status(
            Path(rollout_path), session_id in escalation_threads
        )
        sessions.append(
            {
                "id": session_id,
                "cwd": cwd,
                "status": status,
                "updatedAt": updated_at,
            }
        )
    return sessions


def list_claude_agents() -> tuple[list[dict[str, Any]], set[str]]:
    result = subprocess.run(
        [str(CLAUDE), "agents", "--json"],
        capture_output=True,
        text=True,
        timeout=3,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("Claude roster command failed")
    payload = json.loads(result.stdout)
    if not isinstance(payload, list):
        raise RuntimeError("Claude roster was not a JSON array")
    sessions = [item for item in payload if isinstance(item, dict)]
    keys = {key for item in sessions for key in item.keys() if isinstance(key, str)}
    return sessions, keys


def claude_desktop_session(
    path: Path, permission_sessions: set[str]
) -> dict[str, Any] | None:
    try:
        with path.open("rb") as stream:
            stream.seek(0, os.SEEK_END)
            size = stream.tell()
            stream.seek(max(0, size - 512_000))
            if stream.tell() > 0:
                stream.readline()
            lines = stream.readlines()
    except OSError:
        return None

    session_id: str | None = None
    cwd: str | None = None
    last_timestamp: str | None = None
    state = "unknown"
    outstanding_questions: set[str] = set()

    for raw_line in lines:
        try:
            envelope = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(envelope, dict):
            continue
        candidate_id = envelope.get("sessionId")
        candidate_cwd = envelope.get("cwd")
        timestamp = envelope.get("timestamp")
        if isinstance(candidate_id, str):
            session_id = candidate_id
        if isinstance(candidate_cwd, str):
            cwd = candidate_cwd
        if isinstance(timestamp, str):
            last_timestamp = timestamp

        entry_type = envelope.get("type")
        message = envelope.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if entry_type == "user":
            if isinstance(content, str):
                state = "working"
            elif isinstance(content, list):
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if (
                        item.get("type") == "text"
                        and item.get("text") == "[Request interrupted by user]"
                    ):
                        outstanding_questions.clear()
                        state = "idle"
                    elif item.get("type") == "tool_result":
                        tool_id = item.get("tool_use_id")
                        if isinstance(tool_id, str):
                            outstanding_questions.discard(tool_id)
                        state = "working"
        elif entry_type == "assistant" and isinstance(content, list):
            saw_text = False
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "text":
                    saw_text = True
                elif item.get("type") == "tool_use":
                    state = "working"
                    if item.get("name") == "AskUserQuestion":
                        tool_id = item.get("id")
                        if isinstance(tool_id, str):
                            outstanding_questions.add(tool_id)
            if saw_text and not outstanding_questions:
                state = "idle"

    if not session_id or not cwd:
        return None
    if session_id in permission_sessions:
        state = "waiting_for_permission"
    elif outstanding_questions:
        state = "waiting_for_input"
    return {
        "sessionId": session_id,
        "cwd": cwd,
        "state": state,
        "lastActivity": last_timestamp,
    }


def claude_permission_sessions() -> set[str]:
    try:
        with CLAUDE_DESKTOP_LOG.open("rb") as stream:
            stream.seek(0, os.SEEK_END)
            size = stream.tell()
            stream.seek(max(0, size - 1_000_000))
            if stream.tell() > 0:
                stream.readline()
            lines = stream.readlines()
    except OSError:
        return set()

    emitted = re.compile(
        rb"Emitted tool permission request ([0-9a-f-]+) for ([A-Za-z0-9_-]+) in session (local_[0-9a-f-]+)"
    )
    received = re.compile(rb"Received permission response for ([0-9a-f-]+):")
    outstanding: dict[str, str] = {}
    for line in lines:
        emitted_match = emitted.search(line)
        if emitted_match:
            tool_name = emitted_match.group(2).decode()
            if tool_name != "AskUserQuestion":
                outstanding[emitted_match.group(1).decode()] = emitted_match.group(3).decode()
        received_match = received.search(line)
        if received_match:
            outstanding.pop(received_match.group(1).decode(), None)

    return set(outstanding.values())


def claude_desktop_metadata() -> dict[str, tuple[str, str]]:
    sessions: dict[str, tuple[str, str]] = {}
    try:
        metadata_paths = CLAUDE_DESKTOP_SESSIONS.rglob("*.json")
        for metadata_path in metadata_paths:
            try:
                metadata = json.loads(metadata_path.read_bytes())
            except (OSError, json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(metadata, dict):
                continue
            local_session_id = metadata.get("sessionId")
            cli_session_id = metadata.get("cliSessionId")
            cwd = metadata.get("cwd")
            if all(isinstance(value, str) for value in (local_session_id, cli_session_id, cwd)):
                sessions[cli_session_id] = (local_session_id, cwd)
    except OSError:
        pass
    return sessions


def list_claude_desktop() -> list[dict[str, Any]]:
    cutoff = time.time() - 3600
    candidates: list[tuple[float, Path]] = []
    try:
        paths = CLAUDE_PROJECTS.rglob("*.jsonl")
        for path in paths:
            try:
                modified = path.stat().st_mtime
            except OSError:
                continue
            if modified >= cutoff:
                candidates.append((modified, path))
    except OSError:
        return []
    candidates.sort(reverse=True)
    metadata = claude_desktop_metadata()
    permission_local_sessions = claude_permission_sessions()
    sessions: list[dict[str, Any]] = []
    for _, path in candidates[:50]:
        cli_session_id = path.stem
        desktop_identity = metadata.get(cli_session_id)
        if desktop_identity is None:
            continue
        local_session_id, registered_cwd = desktop_identity
        permission_cli_sessions = (
            {cli_session_id} if local_session_id in permission_local_sessions else set()
        )
        session = claude_desktop_session(path, permission_cli_sessions)
        if session is None:
            continue
        session["sessionId"] = local_session_id
        session["cwd"] = registered_cwd
        sessions.append(session)
    return sessions


def print_roster(observations: list[Observation], elapsed: float) -> None:
    print(f"\nmonotonic={elapsed:.3f}s")
    print(
        "provider | session-id | label/cwd | state | waiting-on | confidence | "
        "last-activity | native-handle"
    )
    if not observations:
        print("- | - | - | unknown | - | unknown | - | unavailable")
    for observation in observations:
        print(observation.row())
    sys.stdout.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="print one roster and exit")
    parser.add_argument("--interval", type=float, default=2.0)
    args = parser.parse_args()

    if args.interval <= 0:
        parser.error("--interval must be positive")

    started = time.monotonic()
    while True:
            observations: list[Observation] = []
            try:
                claude_sessions, claude_keys = list_claude_agents()
                claude_sessions.extend(list_claude_desktop())
                observations.extend(normalize_claude(item) for item in claude_sessions)
                if claude_keys:
                    print("claude-record-keys=" + ",".join(sorted(claude_keys)))
            except (json.JSONDecodeError, OSError, RuntimeError, subprocess.TimeoutExpired):
                observations.append(
                    Observation("claude", "-", "-", "unknown", "-", "stale", "-", "unavailable")
                )

            try:
                observations.extend(normalize_codex(item) for item in list_codex())
            except (OSError, RuntimeError, sqlite3.Error):
                observations.append(
                    Observation("codex", "-", "-", "unknown", "-", "stale", "-", "unavailable")
                )

            rank = {"waiting": 0, "working": 1, "idle": 2, "done": 3, "unknown": 4}
            observations.sort(key=lambda item: (rank[item.state], item.provider, item.session_id))
            print_roster(observations, time.monotonic() - started)
            if args.once:
                break
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
