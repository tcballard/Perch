# ADR 0001: Observation boundaries and scalable provider integration

- **Status:** Proposed
- **Date:** 2026-07-18
- **Decision owners:** Perch maintainers

## Context

Perch must expand beyond its initial Codex Desktop and Claude Desktop sources
without duplicating discovery, parsing, lifecycle reduction, and focus logic for
every provider. Several agent products expose compatible event families, but
their brands, runtime surfaces, versions, and available evidence differ.

Perch is an attention monitor, not an agent control surface. Scale must not
weaken its core guarantee: `waiting` means Perch has current, explicit evidence
of a human handoff. It must never imply urgency from process existence, prose,
silence, or an unsupported event.

## Decision

### Observation tiers

Perch supports two explicit tiers:

1. **Zero-touch observation** uses validated, already-local provider artifacts
   and services. It requires no provider configuration change and remains the
   default.
2. **Enhanced observation** uses observation-only hooks installed through an
   explicit, reversible setup action. Setup must offer preview, status, repair,
   and surgical uninstall, and may alter only Perch-owned integration entries.

Installing or removing an integration is not permission to mutate an agent
session. Perch must never answer, approve, deny, dismiss, interrupt, start,
stop, assign, or write content into a provider session. The only runtime side
effect permitted by the product constitution is a separately validated OS
focus or deep-link action initiated by the user.

### Identity model

Observation identity is split into four non-interchangeable values:

- `ProviderID`: the agent product or brand, such as Claude or Codex.
- `RuntimeSurfaceID`: a concrete surface, such as `claude.cli`,
  `claude.desktop`, `codex.cli`, or `codex.desktop`.
- `SourceID`: one acquisition source, such as a hook stream, transcript watcher,
  local database poller, process sampler, or structured local service.
- `SessionKey`: `ProviderID + RuntimeSurfaceID + provider-local session ID`.

Coordinator tasks, health, backoff, and snapshots are keyed by `SourceID`.
Evidence from multiple sources is reconciled under `SessionKey`; it must not be
overwritten merely because it shares a provider.

### Provider modules and capabilities

A provider integration is a small descriptor composed from reusable parts:

```text
Provider descriptor
  + protocol-family decoder
  + runtime surfaces
  + observation sources
  + declared capabilities
  + version and fixture qualification
```

Protocol-family decoders may be shared across compatible providers. Sharing a
decoder does not qualify a provider: every provider/runtime/version combination
must pass its own controlled validation before Perch advertises support.

Capabilities are declared, not inferred. At minimum they describe observation
tier, supported runtime surfaces, authoritative lifecycle/handoff event kinds,
typed attention reasons, focus availability, supported schema/version range,
and recovery behavior. Partial integrations must be shown as partial; process
liveness alone is presence, not attention support.

### Evidence boundary

Sources emit typed, versioned evidence rather than final `AgentSession` state.
The common envelope contains only the minimum normalized metadata: schema
version, stable `EvidenceID`, `SessionKey`, `SourceID`, event and observation
timestamps, event kind, optional correlation token, authority, and expiry.
Every batch also carries a monotonically increasing sequence scoped to its
source so duplicate, replayed, and reordered input cannot reopen a handoff.

The initial event vocabulary is:

- `sessionSeen`
- `workBegan`
- `handoffOpened(token, reason)`
- `handoffClosed(token)`
- `workEnded`
- `sessionEnded`
- `heartbeat`

`AttentionReason` is a closed typed value: `.input`, `.permission`, `.choice`,
or `.review`. Display strings are derived from it; they are never parsed to
recover meaning. Unsupported reasons or event shapes produce `unknown`, not a
guessed category. Raw prompts, responses, commands, transcript bodies, and
secrets must be discarded at the provider boundary.

Evidence transport supports explicit snapshot and delta batches. A snapshot
replaces only the emitting source's contribution; a delta changes only the
identified session/evidence. Sources do not directly construct final roster
rows.

The first migration keeps Codex Desktop and Claude Desktop behind a narrowly
named legacy snapshot-normalization shim. Those validated decoders reconstruct
one current lifecycle claim from their existing local artifacts, while the
shared reducer owns identity, freshness, capability enforcement, conflicts,
confidence, and final projection. The shim is restricted to the
`perch.local-snapshot.v1` contract and snapshot batches. It is not a reusable
protocol-family decoder; event-level open/close decoding remains mandatory
before a third provider or delta source lands.

### Reducer boundary

One pure `AttentionReducer` owns lifecycle and confidence semantics for every
provider:

- Only a current, authoritative `handoffOpened` may produce `waiting`.
- A matching close, abort, work/session end, expiry, or authoritative
  contradiction clears that wait.
- Silence never means `idle`, `done`, or `waiting`.
- Process existence proves presence only.
- Unsupported, ambiguous, conflicting, reordered, or uncorrelatable evidence
  fails closed to `unknown`.
- Source failure immediately removes its urgent contribution; a neutral
  stale/unknown row may remain for a bounded period.
- `waitingSince` comes from the opening handoff event, not UI discovery time.
- Confidence (`observed`, `inferred`, `stale`, `unknown`) is an assessment
  output, not a provider-supplied conclusion.

Navigation is outside the reducer. Sources may emit sanitized `FocusHint`
values, which independent focus resolvers validate before any OS action.

### Observation-only relay

Enhanced hooks write to a local, user-scoped, one-way relay. The relay and hook
helper must:

- have no command or decision channel from Perch back into the provider;
- use a versioned, bounded envelope over a local Unix-domain socket;
- validate size and schema before decoding and discard unknown input;
- complete within a strict timeout and fail open when Perch is absent, slow, or
  broken;
- never wait for UI state or a human decision;
- emit no stdout unless the provider contract requires a fixed, documented
  pass-through response; and
- never convey an approval, denial, answer, prompt, or session command.

Hook installation must be opt-in and independently reversible. Runtime evidence
and session content are memory-only. Except for explicitly requested setup
metadata/configuration, Perch persists no observations or history, opens no
network connection, performs no telemetry or analytics, and writes no raw
payloads to logs.

## Consequences

### Positive

- Ten provider brands can be represented by a smaller number of protocol-family
  decoders without provider-specific state machines.
- CLI and desktop runtimes, and multiple sources for one session, no longer
  collide.
- A single reducer preserves Perch's confidence and fail-closed guarantees.
- Observation, navigation, setup, and presentation can evolve and fail
  independently.
- Provider breadth remains auditable through an explicit capability matrix.

### Costs and risks

- The identity and evidence migration precedes visible provider expansion.
- Hook contracts and configuration formats create ongoing qualification and
  repair work.
- Some providers will remain presence-only until they expose authoritative
  human-handoff evidence.
- Opt-in setup adds a narrow configuration-write surface that requires exact
  ownership, preview, rollback, and privacy tests.
- Shared protocol shape does not remove the need for provider-specific live
  validation.

## Alternatives considered

- **One final-state adapter per provider:** rejected because it duplicates
  lifecycle policy, conflates acquisition with assessment, and scales failures
  by provider count.
- **Zero-touch sources only:** retained as the default tier but rejected as the
  sole strategy because several CLI harnesses cannot expose reliable explicit
  waits without supported hooks.
- **Bidirectional approval/answer bridge:** rejected because it violates the
  product constitution and turns observation failure into agent-session risk.
- **Fork or copy Open Island:** rejected because Perch requires different
  product boundaries and independent licensing/provenance.
- **Dynamic runtime plug-ins in the first implementation:** deferred. A
  compile-time registry is simpler to validate and sufficient for the current
  scale target.

## Provenance boundary

This is an independent implementation. No Open Island code, tests, fixtures,
assets, payload samples, installer snippets, or configuration fragments may be
copied or translated into Perch. Implementation inputs must be provider-owned
documentation, public provider contracts, macOS APIs, and fresh sanitized
captures produced specifically for Perch. Each integration records those
sources and its validated provider/runtime versions.

The team has inspected Open Island at an architectural level, so this policy is
not represented as a formal legal clean-room process. It is a strict provenance
boundary for an independently authored Apache-2.0 implementation; licensing
questions remain subject to maintainer review.

## Staged implementation

1. Add `RuntimeSurfaceID`, `SourceID`, `SessionKey`, typed `AttentionReason`,
   evidence envelopes, and reducer contract tests.
2. Wrap existing Codex Desktop and Claude Desktop acquisition as legacy
   snapshot sources without changing visible behavior. Centralize assessment in
   the shared reducer, then replace their snapshot-normalization shims with
   event-level decoding.
3. Re-key coordination and health by source/session, add shared process and
   filesystem acquisition services, and separate focus resolvers.
4. Add the compile-time provider registry, capability declarations, and common
   provider-qualification suite.
5. Add a source-instance epoch/reset contract, then implement the opt-in
   one-way relay and isolated setup tool, including preview, repair, uninstall,
   fail-open, privacy, and absence tests.
6. Add protocol-family decoders, then qualify each provider/runtime/version
   independently. Do not advertise a provider until its declared capabilities
   pass fixtures and a controlled live check.

No third provider should land before stages 1–4 preserve all current transition,
latency, isolation, privacy, and negative-evidence guarantees.
