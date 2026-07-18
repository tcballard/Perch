# Perch

Perch is a local macOS menu-bar monitor that answers one question: which coding
agent is waiting for me right now?

Perch observes existing sessions and can focus a validated native surface. It
does not create tasks, answer prompts, grant approvals, control agents, or send
provider data over the network.

PR #1 delivered the internal `v0.0.1` observation-engine foundation. The
`v0.0.2` panel adds a waiting-first attention layer: a compact ambient summary,
an actionable human-handoff queue, and secondary access to all observed
activity. The product path toward the first signed `v0.1.0` release is
documented in [ROADMAP.md](ROADMAP.md). The design decision is recorded in
[docs/design/v0.0.2-attention-layer.md](docs/design/v0.0.2-attention-layer.md).
The provider-scaling identity, evidence, and reducer boundaries are recorded in
[ADR 0001](docs/adr/0001-observation-boundaries.md).

## Current support

| Provider | Validated version | Observation | Focus | Known limit |
| --- | --- | --- | --- | --- |
| Codex Desktop | `0.144.0-alpha.4`, `0.144.2`, `0.145.0-alpha.18` | Local thread database and structured rollout events | Specific task through `codex://threads/<id>` | Other versions fail closed to `unknown` |
| Claude Desktop | Claude Code `2.1.205` | Desktop registry, registered structured transcripts, and metadata-only permission events | Unavailable | No validated task-level deep link |

Claude Code running in Ghostty is intentionally unsupported in v0.1 because
its local roster did not reliably retain the foreground session.

## States and confidence

- `waiting` requires explicit current evidence of a human input, choice, or
  permission request.
- `working` requires a validated active task or tool-execution signal.
- `idle` requires a known neutral session state; silence alone is insufficient.
- `done` requires an explicit completion event.
- `unknown` is used for missing, malformed, contradictory, or unsupported
  evidence.

Confidence is reported separately as `observed`, `inferred`, `stale`, or
`unknown`. When an adapter fails, Perch immediately clears any previous waiting
state, retains the session as `unknown`/`stale` for 15 seconds, then removes it.

## Privacy and permissions

Observation is local and read-only. Perch does not persist session content,
log raw prompts, or use network services. Debug timing logs contain source
identifiers, durations, counts, and transition latency only. The app is currently
an unsandboxed developer utility so it can read the providers' local metadata.

Focusing a Codex task asks macOS to open a validated provider URL. Opening the
Perch panel never changes an agent session and Perch never focuses anything
automatically.

## Build and test

Requirements: Apple Silicon Mac, macOS 14 or later, and Xcode 26 or later.

```sh
./script/build_and_run.sh
```

Run the Swift tests:

```sh
xcodebuild \
  -project Perch.xcodeproj \
  -scheme Perch \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Run the disposable provider-state regression suite:

```sh
python3 -m unittest discover -s tests -v
```

The evidence, reproduction steps, provider limitations, and gate decision are
recorded in [SPIKE-findings.md](SPIKE-findings.md).
