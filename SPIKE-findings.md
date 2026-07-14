# Perch provider-state spike findings

Date: 2026-07-14
Decision: **GO**

## Gate conclusion

The provider-state gate passes for Claude Desktop and Codex Desktop. Both
providers enumerate stable live sessions, distinguish active work from explicit
human input and permission waits, detected all three controlled cycles within
one probe interval of the first external event, and produced no false waits for
the five controlled prompt-like negatives. Evidence is local and read-only.
Codex additionally focused the correct real waiting task through its stable
provider URL without modifying the task. Ghostty-hosted Claude Code is excluded
from v0.1 because its foreground roster signal was not stable enough.

Approved product configuration, to be used only if the provider gate passes:

- Xcode project with SwiftUI and narrow AppKit integration;
- bundle identifier `com.tcballard.perch`;
- macOS 14.0 minimum on Apple Silicon;
- automatic development signing with team `R8HXTBY3NM`;
- menu-bar-only, unsandboxed Developer ID distribution target;
- organization name `Tom Ballard`.

## Environment orientation

| Item | Observed value |
| --- | --- |
| Repository | Git repository with no commits or tracked files |
| Initial branch | unborn `master` |
| Work branch | `codex/perch-blocked-orientation` |
| macOS | 27.0 (build 26A5378j), arm64 |
| Xcode | 26.3 (build 17C529) |
| Swift | Apple Swift 6.2.4 |
| Claude Code CLI | 2.1.173 at `/opt/homebrew/bin/claude` |
| Claude desktop integrated Claude Code | 2.1.205 |
| Codex CLI | 0.144.0-alpha.4 inside ChatGPT.app |
| tmux | not installed |

Commands used for orientation:

```sh
git status --short --branch
find . -maxdepth 3 -type f -not -path './.git/*'
sw_vers
uname -m
/opt/homebrew/bin/claude --version
/Applications/ChatGPT.app/Contents/Resources/codex --version
tmux -V
xcodebuild -version
swift --version
```

There was no documented baseline build, test, lint, or format command to run.

## Provider evidence matrix

Machine-readable local interfaces passed the controlled trials for both
required desktop providers.

| Provider/version | Sessions enumerable | Working detectable | Waiting detectable | Signal source | Confidence | Focus handle | Transition latency | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude desktop / Claude Code 2.1.205 | Yes, via desktop registry plus registered structured transcripts | Yes | Yes: unmatched `AskUserQuestion` and desktop permission request IDs | Local metadata, structured JSONL envelopes, metadata-only desktop log events | Observed | Owning app only; task-level handle not validated | Probe cadence <=1s after event; three cycles detected | PASS for state |
| Claude Code CLI 2.1.173 in Ghostty | Intermittently; `agents --json` lost the foreground session while it remained visibly waiting | Not reliable | Not reliable | Unstable CLI agent roster; foreground transcript did not expose the visible wait | Unknown | Not tested | Not measurable reliably | UNSUPPORTED FOR v0.1 |
| Codex desktop / CLI 0.144.0-alpha.4 | Yes, via local thread index | Yes | Yes: unmatched `request_user_input`; escalated exec plus user reviewer | Read-only state DB, structured rollout envelopes, metadata-key log query | Observed | Stable task ID via `codex://threads/<id>`; validated on a real waiting task | Probe cadence <=1s after event; three cycles detected | PASS for state and focus |

The generated Codex 0.144.0-alpha.4 app-server schema defines thread states
`notLoaded`, `idle`, `systemError`, and `active`; active threads additionally
carry explicit `waitingOnApproval` and `waitingOnUserInput` flags. This is a
promising structured contract, not proof of desktop-session visibility. Claude
2.1.173 documents an `agents --json` scripting interface, but its live record
shape and coverage of desktop and Ghostty sessions still require validation.

The disposable normalised roster probe is at `spikes/provider-state/probe.py`.
It redacts content by construction and defaults all unrecognized shapes to
`unknown`.

During the first production-adapter run, the embedded CLI reported `0.144.2`
while the enclosing app remained version `26.707.71524`. The adapter correctly
degraded every row to `unknown`. The live `0.144.2` rollout was then checked
against the sanitized fixture fields and retained the validated event-envelope,
call-ID, abort, and task lifecycle shapes. Compatibility is therefore explicitly
allowed for `0.144.0-alpha.4` and `0.144.2` only; later versions still fail
closed until separately validated.

## Controlled transition evidence

### Codex desktop

Three explicit input cycles were observed for thread
`019f5a27-4e09-7030-bf80-166ba4ca6d53`:

| Cycle | Working event | Waiting event | Resumed event | Idle event | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | 06:27:18Z | 06:27:23Z | 06:29:01Z timeout result | 06:29:06Z | Waiting detected and safely cleared on timeout |
| 2 | 06:31:28Z | 06:31:30Z | 06:31:36Z answer result | 06:31:37Z | PASS |
| 3 | 06:33:03Z | 06:33:05Z | 06:33:09Z answer result | 06:33:18Z | PASS |

A native external-write approval wait was observed from 06:41:27Z until its
matching tool output at 06:44:56Z; the session returned to idle at 06:45:04Z.
The probe selected only the presence of the exact
`sandbox_permissions=require_escalated` metadata and never selected the
command body.

Two concurrent Codex tasks were observed in different states: the controlled
`perch-codex-b` task was waiting on structured user input while the Perch task
was working. Their provider/session keys remained distinct.

Task-level focus was validated with stable thread ID
`019f5ee8-576e-74b3-9b84-a5b73b3ad1d5`. With another Codex task visible, opening
`codex://threads/019f5ee8-576e-74b3-9b84-a5b73b3ad1d5` selected the correct
waiting `perch-codex-b` task. The operation neither answered nor otherwise
changed the waiting session.

Abrupt termination was exercised by stopping the same task during active work.
Codex emitted an explicit structured `turn_aborted` event at 05:20:28Z. The
probe initially exposed a missing lifecycle rule by leaving the session
`working`; after adding the observed abort rule, it immediately cleared active
work and all outstanding input, approval, and exec call IDs and reported the
session `idle`. No disappearance or inactivity heuristic was used.

### Claude desktop

Three explicit input cycles were observed for the original desktop task:

| Cycle | Working event | Waiting event | Resumed event | Idle event | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | 16:29:17Z | 16:29:41Z | 16:32:31Z | 16:32:44Z | PASS |
| 2 | 16:34:18Z | 16:35:55Z | 16:36:32Z | 16:37:35Z | PASS |
| 3 | 16:51:06Z | 16:51:10Z | 16:52:49Z | 16:55:03Z | PASS |

The long intervals before Claude emitted a question remained `working`; the
probe changed to `waiting` only after the externally detectable structured
`AskUserQuestion` event. A native Bash approval request was matched by opaque
request ID and stable local desktop session ID. It cleared on the corresponding
permission response/tool result and returned to idle; the approved disposable
marker was created.

Two registered Claude desktop tasks were observed concurrently: stable desktop
session `local_550c...` waited for input in `perch-claude-b` while
`local_65e...` remained idle. Orphaned CLI transcripts were excluded, and
desktop `local_*` IDs—not replaceable CLI transcript IDs—were used as provider
session keys.

Abrupt termination was exercised in the registered `perch-claude-b` desktop
task. Claude wrote an exact structured user-side text item equal to
`[Request interrupted by user]` at 05:28:37Z. The probe matches only that
observed provider marker, clears outstanding questions, and reports the stable
desktop session `idle`; it does not treat arbitrary text containing words such
as “interrupt” or “cancel” as lifecycle evidence.

## Ambiguous negative samples

For each provider, one completed ordinary text response contained these five
controlled prompt-like phrases: a proceed question, a permission statement, a
two-option choice, an approval-wait statement, and a review question. Neither
response invoked the provider's structured input tool, and both remained
`idle`; no phrase was parsed as waiting.

Claude also produced a real conversational “Should I proceed?” response before
the native Bash test. Because it was ordinary assistant text with no structured
tool or permission event, the probe correctly left it idle. This confirms that
visible prompt-like language alone is insufficient.

## Signal limitations found

- `claude agents --json` returned an empty array while a Claude desktop coding
  task was visibly waiting; it covers background agents, not this desktop host.
- A separately launched Codex app-server enumerated saved threads but marked
  the live desktop task `notLoaded`; it cannot supply the desktop runtime state.
- Codex `request_user_input` availability varies by collaboration mode. Native
  approval waits remain a separate supported signal.
- Claude desktop describes `AskUserQuestion` as a tool permission in its log;
  normalization must map that tool to human input, not generic permission.
- Claude Code in Ghostty is excluded from v0.1 because `claude agents --json`
  briefly enumerated the foreground session and then returned an empty roster
  repeatedly while the same session remained visibly waiting. The transcript
  also lacked an outstanding structured `AskUserQuestion` for that visible
  wait, so no reliable local state contract was found.
- Provider model latency before the first structured waiting event is not
  Perch detection latency. The one-second spike cadence observed transitions
  within the required three-second window after the provider event appeared.

## Permissions, privacy, and external effects

No provider session content was retained or written. Inspection so far was
limited to command help, generated protocol schemas, file/table names, process
executable paths, and sanitized structured status fields. One Codex task was
focused through its provider-defined task URL; it was not controlled or
modified. The minimum permission footprint and denial behaviour remain under
test.

## Missing setup

The required state-transition, negative-sample, concurrency, lifecycle, and
Codex focus trials are complete. No additional live-provider setup is required
for the gate.

## Production implementation

None. In particular, no menu-bar app, domain model, adapter API, shared
framework, persistence, or visual system was scaffolded.

## Sanitized regression fixtures

`python3 -m unittest discover -s tests -v` passes five content-minimized tests
covering Codex input wait/resume, Codex abort cleanup, Claude input wait/resume,
Claude's exact interruption marker, and prompt-like ordinary text remaining
idle. The fixtures contain invented IDs, paths, timestamps, and text; they do
not retain provider-session content.

## Recommended next step

Proceed with the smallest production vertical slice for the two validated
desktop providers. Preserve the spike's exact record-shape and version
assumptions, default unknown versions to `unknown`, and keep Ghostty support
out of v0.1.
