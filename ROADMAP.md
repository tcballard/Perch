# Perch roadmap

Status: active planning baseline
Updated: 2026-07-14

Perch is an attention layer first, with cross-provider navigation available when
needed. Its user questions, in priority order, are:

1. Does anything need me?
2. What needs me, why, and for how long?
3. What else is happening across my projects and providers?

Projects are the primary user-facing grouping. Providers are secondary metadata
and filters. Perch observes and focuses; it never orchestrates.

## Product constitution

- `waiting` requires explicit current human-handoff evidence. Ambiguity is
  `unknown`, never urgent.
- Perch never answers, approves, dismisses, starts, stops, assigns, or writes
  into provider sessions.
- Provider mechanics remain behind independently disableable adapters; slow or
  failed providers remain isolated and immediately clear prior waiting state.
- Observation stays local and read-only. No raw prompts, transcript bodies,
  paths, or secrets are persisted or logged.
- No cloud services, analytics, network telemetry, or conversation history.
- macOS 14+ on Apple Silicon; bundle identifier `com.tcballard.perch`.

## v0.0.1 — Observation engine — complete

### Product outcome

The internal foundation proves that Codex Desktop and Claude Desktop can be
observed locally and conservatively, with an exact menu-bar waiting count and
sub-three-second transition visibility.

### Included scope

- Provider-neutral session and confidence model.
- Validated Codex and Claude adapters with safe unsupported-version behavior.
- Independent monotonic one-second polling, bounded processes, and caches.
- Immediate waiting-state clearing on ambiguity and 15-second stale retention.
- Diagnostic all-session panel and exact menu-bar waiting count.
- Validated Codex task focus; honest unavailable focus for Claude.
- Transition, parser, isolation, latency, privacy, cache, and focus coverage.

### Explicitly excluded

- Finished product information hierarchy and complete accessibility behavior.
- Distribution signing, notarization, release artifacts, and launch at login.
- Replies, approvals, provider mutation, additional providers, and Ghostty.

### Decisions

- Polling remains appropriate while the measured target is met.
- Unknown evidence fails closed and never inherits a prior waiting state.
- PR #1 is the observation engine and diagnostic vertical slice, not the
  finished experience.

### Acceptance and manual verification

- Ten Swift tests and five sanitized provider-spike tests pass.
- Five-session transitions, provider isolation, version invalidation, and
  prompt-like negative samples are deterministic.
- Real Codex and Claude waits appeared within three seconds; Codex task focus
  opened the correct source without changing the session.
- A process-scoped normal run opened no network descriptors.

### Risks and deferred work

- Provider record shapes and versions can change without notice.
- Claude has no validated task-level focus handle.
- The diagnostic roster gives non-actionable states too much visual weight.

## v0.0.2 — Waiting-first attention layer

### Product outcome

Outstanding human handoffs are immediately understandable.

### Included scope

- Waiting-first default panel and calm zero-wait state.
- Project identity, normalized required-action category, wait duration, provider
  as secondary metadata, and one honest focus affordance.
- Bounded multiple-wait behavior and secondary in-panel access to All activity.
- Recommended hybrid presentation: compact ambient summary plus a highly
  legible waiting stack.
- Keyboard traversal, VoiceOver grouping, semantic contrast, and a static
  reduced-motion equivalent.
- Deterministic 0, 1, 3, 8, and 20-agent presentation fixtures.

### Explicitly excluded

- A permanent expanded navigator window; that belongs to v0.0.3.
- Agent replies, approvals, dismissals, notifications, sounds, auto-focus, or
  any implication that visiting a handoff resolves it.
- Notch overlays, custom always-on-top panels, new providers, hooks, watchers,
  persistence, networking, or third-party source/assets.

### Decisions

- The waiting stack is the semantic and keyboard source of truth.
- Project and required action lead; provider is secondary.
- Ambient presences are a redundant, non-interactive state summary. At eight or
  more observed agents, background states aggregate rather than multiply.
- Unknown/stale sessions never enter the attention area and remain neutral.
- All activity is an in-panel secondary mode for v0.0.2.

### Acceptance criteria

- Zero waits reads “Nothing needs you” without listing background sessions.
- Every waiting handoff shows project, allow-listed action category, duration,
  secondary provider/confidence metadata, and correct focus availability.
- Only waiting sessions appear in the default actionable stack; All activity
  contains every current normalized session without changing the exact count.
- 8- and 20-agent fixtures remain legible in the menu-bar panel through ambient
  aggregation and a bounded/scrollable queue.
- All controls are keyboard reachable and meaningfully labelled for VoiceOver.
- Reduce Motion communicates identical state with no positional motion.
- Existing transition, isolation, parser, privacy, and latency checks remain
  green, including a normal run with no Perch network traffic.

### Manual verification

- Exercise 0, 1, 3, 8, and 20-agent fixtures in light/dark mode, increased
  contrast, and Reduce Motion.
- Navigate the complete panel by keyboard and inspect its VoiceOver hierarchy.
- Trigger live Codex and Claude waits; verify count, category, duration, latency,
  Codex focus, and Claude focus-unavailable behavior.

### Risks and deferred work

- Ambient character can become decorative noise; remove it if recognition time
  or accessibility is worse than the pure inbox.
- Project labels currently derive from sanitized working-directory metadata.
- Action categories must remain a closed mapping; unsupported evidence cannot
  be paraphrased or guessed.

## v0.0.3 — Expanded cross-provider navigator

### Product outcome

Users can optionally browse all agent work without weakening Perch’s
attention-first identity.

### Included scope

- An expanded native window with projects as the primary grouping.
- Provider sessions nested beneath projects.
- Provider and state filters, with waiting visibly prioritized.
- Clear transition between the compact panel and expanded navigator.
- Stable keyboard selection, native sidebar/detail behavior, and window-state
  restoration appropriate to macOS.

### Explicitly excluded

- Making the navigator the default Perch surface.
- Provider-first navigation, task boards, workflow management, replies, or
  session controls.

### Decisions

- Use a native SwiftUI `WindowGroup` and project-first sidebar rather than
  cramming navigation into the menu-bar panel.
- Reuse the normalized in-memory roster; do not add history persistence.

### Acceptance criteria

- Opening the navigator is optional and never steals focus automatically.
- Project groups and filters remain correct as provider snapshots update.
- Waiting priority and focus availability match the compact attention panel.
- Closing/reopening the window preserves only appropriate UI selection state.

### Manual verification

- Exercise multi-project fixtures, filters, keyboard navigation, window
  activation, and focus handoff without modifying provider state.

### Risks and deferred work

- A navigator can pull Perch toward generic session management; attention entry
  points and waiting priority must remain explicit.

## v0.0.4 — Ambient and interaction polish — provisional

### Product outcome

Perch gains restrained personality only where it improves state recognition
without competing with the user’s work.

### Included scope

- Validate ambient presence, state-transition motion, menu-bar treatment, and
  spatial grouping against recognition time and accessibility evidence.
- Refine or remove the v0.0.2 ambient summary.

### Explicitly excluded

- Game mechanics, constant decorative animation, custom physics, notification
  theater, or information available only through motion.

### Decisions

- Keep this milestone separate only if v0.0.2 testing shows ambient behavior is
  useful but needs deeper refinement.
- Fold small successful refinements into v0.0.2/v0.0.3 when low risk.
- Drop the ambient model entirely if it slows recognition, harms accessibility,
  or cannot aggregate cleanly at 20 agents.

### Acceptance criteria and manual verification

- Comparative testing shows no slower identification of waiting work than the
  pure inbox baseline.
- Reduce Motion, VoiceOver, contrast, and keyboard behavior retain full parity.
- CPU and polling latency remain within the v0.0.1 baseline envelope.

### Risks and deferred work

- Visual novelty can mask weak utility; the milestone has an explicit deletion
  outcome rather than a presumption that ambience ships.

## v0.0.5 — Release-candidate hardening

### Product outcome

Perch is operationally ready for clean-account distribution testing.

### Included scope

- Native Settings and About surfaces.
- Provider availability, health, unsupported-version, permission, and degraded
  state UX.
- Consent-based Launch at Login using standard macOS APIs.
- Release build configuration, Hardened Runtime, minimum entitlements, clean
  account verification, packaging scripts, and release checklist.

### Explicitly excluded

- Public release, automatic updates, Homebrew Cask, cloud services, analytics,
  default notifications, and additional providers.

### Decisions

- Settings reports and explains adapter state but does not mutate provider
  configuration.
- Launch at Login is off by default, explicit, and reversible.
- No broad entitlement is added without demonstrated runtime need.

### Acceptance criteria and manual verification

- Release build passes automated tests and Hardened Runtime/entitlement audit.
- Clean macOS account verifies first launch, denial, unsupported versions,
  provider discovery, launch-at-login consent, and removal.
- Packaging/release steps are repeatable without storing credentials in Git.

### Risks and deferred work

- Unsandboxed local metadata access must remain narrowly explained and audited.
- Provider version churn may block observation during release qualification.

## v0.1.0 — First public-quality release

### Product outcome

Perch is ready to ask other people to install.

### Included scope

- Developer ID signing with `Developer ID Application: Thomas Ballard
  (R8HXTBY3NM)`.
- Hardened Runtime, Apple notarization, stapling, and Gatekeeper validation.
- Installable direct-download artifact.
- Clean-account install, first launch, provider discovery, upgrade-by-replacement,
  and removal checks.
- Current support matrix plus privacy, troubleshooting, and uninstall docs.

### Explicitly excluded

- Homebrew Cask as a release blocker; evaluate it for v0.1.1.
- Automatic updates unless separately approved.
- Any relaxation of the observe-and-focus boundary.

### Decisions

- Direct download is the first distribution channel.
- Signing and notarization evidence is scripted and recorded; credentials stay
  outside the repository.

### Acceptance criteria and manual verification

- `codesign`, notarization, stapler, and `spctl` validation succeed.
- The artifact runs without Xcode on a supported clean account.
- Install, first-launch, discovery, upgrade, and removal instructions are proven.
- A normal runtime produces no unexpected network activity.

### Risks and deferred work

- Notarization depends on Apple service availability and external credentials.
- Homebrew Cask, update delivery, and additional providers follow separately.
