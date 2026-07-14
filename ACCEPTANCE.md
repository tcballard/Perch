# Perch v0.1 acceptance record

Date: 2026-07-14

| Check | Result | Evidence |
| --- | --- | --- |
| A1 — transitions | PASS | Five scripted sessions transition through `working → waiting → working → done`; roster states and waiting count are asserted after every refresh. |
| A2 — priority | PASS | Waiting sessions sort above working sessions and retain the first detected waiting timestamp. |
| A3 — focus | PASS | A real Codex task focused through a validated `codex://threads/<UUID>` URL during the spike. Invalid IDs are rejected and unsupported adapters return `focusUnavailable`. |
| A4 — isolation | PASS | A fast adapter publishes while another is delayed for five seconds; a failed adapter clears waiting and degrades only its own snapshot to `unknown`/`stale`. |
| A5 — local only | PASS | During a normal polling run, `lsof -nP -a -p <Perch PID> -i` was sampled once per second for ten seconds and reported no network descriptors. Provider processes were outside the inspected PID. |
| A6 — no fabrication | PASS | Ordinary assistant text containing prompt-like language remains idle in both provider fixture suites. |
| A7 — version surprise | PASS | Codex only observes versions `0.144.0-alpha.4` and `0.144.2`; Claude only observes `2.1.205`. Other versions produce `unknown` confidence and state. Cache invalidation is tested. |
| A8 — privacy | PASS | Fixtures contain invented identifiers and minimal event shapes. Debug logs contain provider, duration, session count, and transition latency only. |

## Automated verification

```sh
xcodebuild \
  -project Perch.xcodeproj \
  -scheme Perch \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Result: 10 tests passed, 0 failures.

```sh
python3 -m unittest discover -s tests -v
```

Result: 5 tests passed, 0 failures.

## Live timing

Metadata-only debug logs measured normal Codex refreshes at approximately
0.10–0.20 seconds, unchanged Claude refreshes at approximately 0.004 seconds,
and a changed Claude transcript refresh at 1.74 seconds. Each provider polls on
an independent monotonic one-second schedule, keeping the observed paths below
the three-second requirement.

## Manual verification

- Perch showed both Codex and Claude desktop sessions in the menu-bar panel.
- The menu-bar bird and exact waiting count reacted to controlled waits.
- Opening a validated Codex row focused the correct task without answering or
  otherwise modifying it.
- Claude focus remained unavailable because no safe task-level deep link was
  validated.
