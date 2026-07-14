# Provider-state spike

This disposable probe tests whether installed Claude Code and Codex versions
expose enough local structured state for Perch. It is not production adapter
code.

It reads the Claude background-agent JSON roster, recent Claude desktop
structured transcript envelopes, and Codex's local thread index plus structured
event envelopes from recent live rollout files. Output is deliberately restricted
to provider, sanitized ID, working-directory basename, normalized state, an
allow-listed waiting category, confidence, timestamp, and handle availability.
It never prints prompts, transcript bodies, thread titles, previews, commands,
or model output.

Run one sample:

```sh
python3 spikes/provider-state/probe.py --once
```

Watch at the two-second target cadence:

```sh
python3 spikes/provider-state/probe.py
```

The probe opens the Codex state database read-only and parses at most the final
512 KB of each recent rollout in memory. It inspects only envelope types,
timestamps, tool names, opaque call IDs, and whether an exec call explicitly
declares `sandbox_permissions=require_escalated`. For Codex desktop, whose
rollout redacts exec arguments, the probe asks the local logs database whether
that exact metadata key/value occurred for the same thread; it never selects
the log body. Content fields are never emitted or retained.

For Claude desktop, the probe likewise parses at most the final 512 KB of each
recent structured transcript in memory. An unmatched `AskUserQuestion` tool-use
ID is `waiting`; its matching `tool_result` clears the wait. Question text,
choices, messages, and tool input/output content are ignored.

Native Claude permission waits are matched from fixed metadata-only desktop-log
events: an emitted permission request ID and local session ID remain waiting
until the corresponding response ID appears. The local-to-CLI session mapping
comes from Claude's session metadata. Only CLI transcripts currently registered
to a desktop session are enumerated, and the provider key uses the stable local
desktop ID rather than the replaceable CLI transcript ID. Tool input and log
content outside these fixed event shapes are ignored.
