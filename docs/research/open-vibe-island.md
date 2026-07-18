# Open Island and Vibe Island research

Date inspected: 2026-07-14
Purpose: interaction and architecture research for Perch v0.0.2 planning

> Update (2026-07-18): [ADR 0001](../adr/0001-observation-boundaries.md)
> supersedes this note's blanket rejection of provider hooks. Perch may support
> explicit, reversible, observation-only hooks through a one-way local relay;
> bidirectional approval/answer bridges and session mutation remain prohibited.

## Sources inspected

- [Vibe Island](https://vibeisland.app/), including its public product preview.
- [Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island),
  cloned temporarily for read-only inspection of `README.md`, `LICENSE`,
  `docs/architecture.md`, `Package.swift`, app UI structure, and design bundle.

No source or asset was copied into Perch.

## Licence and reuse implication

Open Island is licensed under GNU GPL version 3. Its repository describes a
native SwiftUI/AppKit app and distributes GPL-covered source and assets.

Perch should not incorporate Open Island code or assets without an explicit
licensing decision and a clear architectural need. GPL reuse could impose
copyleft obligations on distributed derivative or combined work. For the
current independently authored Perch codebase, the safe recommendation is to
use only high-level interaction observations and standard macOS patterns. This
note is product-engineering guidance, not legal advice.

Vibe Island is a commercial interaction reference. Its public surface supports
monitoring, approvals, answers, and jump-back. Perch deliberately retains only
the monitoring/focus lesson; approval and answer controls violate Perch’s
constitution.

## Relevant interaction patterns

- A compact status surface near the menu bar reduces context switching.
- Working agents can remain calm background context while an explicit waiting
  state receives stronger position and emphasis.
- A small handoff surface can pair session/project identity, elapsed time, state,
  and jump-back action.
- Spatial grouping can create quick at-a-glance state recognition.
- A non-activating or accessory-style surface supports ambient use without
  stealing focus.

## Architecture observed

Open Island is one Swift package with four targets:

- `OpenIslandApp`: SwiftUI/AppKit shell, menu bar, overlay, settings.
- `OpenIslandCore`: shared models, reducer, transcript discovery, persistence,
  registry, hook installers, and Unix-socket transport.
- `OpenIslandHooks`: CLI invoked by provider hooks.
- `OpenIslandSetup`: provider-configuration installer CLI.

Its event flow sends hook payloads through a Unix-domain socket to an in-app
bridge and central observable model. It restores persisted sessions, discovers
transcripts, reconciles processes, and supports per-terminal jump-back. It also
uses AppKit for overlay placement/panel behavior and Sparkle for updates.

Useful general principles are clean UI/transport separation, a single state
reducer, versioned event shapes, reversible setup, and bounded native surfaces.

## Patterns inappropriate for Perch

- Provider hook installation or modification of provider configuration.
- A CLI/socket bridge that can return approval/denial directives.
- Permission approval, question answering, or any session mutation.
- Persisted session registry/content or conversation-oriented detail UI.
- Provider-first organization or a broad terminal-control matrix.
- Notifications, sound effects, constant animation, and notch-overlay complexity.
- Sparkle/automatic updates before Perch separately approves an update strategy.
- Reusing GPL code/assets without a deliberate licensing decision.

## Reuse opportunities

No direct code or asset reuse is recommended.

Independently implementable ideas based on standard platform conventions:

- Accessory/non-activating native surface behavior.
- A shallow state summary plus explicit accessible handoff stack.
- Optional AppKit interop only where SwiftUI cannot express panel behavior.
- A pure presentation model/reducer separated from provider adapters.

## Risks and maintenance implications

- Spatial UI can become game-like and obscure urgency at 8–20 agents.
- Hook-based architectures may look more responsive but would violate Perch’s
  read-only rule and add third-party configuration maintenance.
- Exact provider and terminal jump-back expands permissions and compatibility
  surface; Perch must keep only validated native handles.
- Mirroring visual identity or assets creates product and licensing risk even
  when the technical implementation differs.
- Reference products evolve rapidly; Perch decisions must be justified by its
  own acceptance tests rather than feature parity.
