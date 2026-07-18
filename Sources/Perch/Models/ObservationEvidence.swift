import Foundation

struct ObservationContractID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let localSnapshotV1 = ObservationContractID(rawValue: "perch.local-snapshot.v1")
    static let eventStreamV1 = ObservationContractID(rawValue: "perch.event-stream.v1")
}

enum ObservationTier: String, Hashable, Sendable {
    case zeroTouch
    case enhanced
}

enum ObservationCapability: String, Hashable, Sendable {
    case sessionDiscovery
    case workState
    case explicitInputWait
    case explicitPermissionWait
    case explicitChoiceWait
    case explicitReviewWait
    case completion
    case focus
}

struct ObservationSourceDescriptor: Hashable, Sendable {
    let id: SourceID
    let provider: ProviderID
    let runtime: RuntimeSurfaceID
    let contract: ObservationContractID
    let tier: ObservationTier
    let capabilities: Set<ObservationCapability>

    static let mockScripted = ObservationSourceDescriptor(
        id: .mockScripted,
        provider: .mock,
        runtime: .mockFixture,
        contract: .localSnapshotV1,
        tier: .zeroTouch,
        capabilities: [.sessionDiscovery, .workState, .explicitChoiceWait, .completion]
    )

    static let codexDesktopLocalState = ObservationSourceDescriptor(
        id: .codexDesktopLocalState,
        provider: .codex,
        runtime: .codexDesktop,
        contract: .localSnapshotV1,
        tier: .zeroTouch,
        capabilities: [.sessionDiscovery, .workState, .explicitInputWait, .explicitPermissionWait, .focus]
    )

    static let claudeDesktopLocalState = ObservationSourceDescriptor(
        id: .claudeDesktopLocalState,
        provider: .claude,
        runtime: .claudeDesktop,
        contract: .localSnapshotV1,
        tier: .zeroTouch,
        capabilities: [.sessionDiscovery, .workState, .explicitInputWait, .explicitPermissionWait]
    )
}

struct EvidenceID: RawRepresentable, Hashable, Sendable {
    let rawValue: String
}

struct HandoffToken: RawRepresentable, Hashable, Sendable {
    let rawValue: String
}

enum EvidenceAuthority: Hashable, Sendable {
    case authoritative
    case supporting
    case presence
}

enum EvidenceKind: Hashable, Sendable {
    case sessionSeen
    case workBegan
    case handoffOpened(token: HandoffToken, reason: AttentionReason)
    case handoffClosed(token: HandoffToken)
    case workEnded
    case sessionEnded
    case heartbeat
}

struct SessionEvidence: Hashable, Sendable {
    static let currentSchemaVersion: UInt = 1

    let schemaVersion: UInt
    let id: EvidenceID
    let session: SessionKey
    let source: SourceID
    let eventAt: Date
    let observedAt: Date
    let expiresAt: Date?
    let authority: EvidenceAuthority
    let kind: EvidenceKind

    init(
        schemaVersion: UInt = SessionEvidence.currentSchemaVersion,
        id: EvidenceID,
        session: SessionKey,
        source: SourceID,
        eventAt: Date,
        observedAt: Date,
        expiresAt: Date? = nil,
        authority: EvidenceAuthority,
        kind: EvidenceKind
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.session = session
        self.source = source
        self.eventAt = eventAt
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.authority = authority
        self.kind = kind
    }
}

struct ObservedSession: Hashable, Sendable {
    let key: SessionKey
    let label: String?
    let workingDirectory: URL?
    let nativeSurface: NativeSurfaceHandle?
    let lastActivity: Date?
    let validatedProviderVersion: String?

    init(
        key: SessionKey,
        label: String? = nil,
        workingDirectory: URL? = nil,
        nativeSurface: NativeSurfaceHandle? = nil,
        lastActivity: Date? = nil,
        validatedProviderVersion: String? = nil
    ) {
        self.key = key
        self.label = label
        self.workingDirectory = workingDirectory
        self.nativeSurface = nativeSurface
        self.lastActivity = lastActivity
        self.validatedProviderVersion = validatedProviderVersion
    }
}

/// Transitional normalization used only by the two validated local snapshot
/// adapters. New protocol-family decoders must emit event-level evidence.
enum LegacySnapshotLifecycleClaim: Hashable, Sendable {
    case presenceOnly
    case workBegan(at: Date)
    case handoffOpened(token: HandoffToken, reason: AttentionReason, at: Date)
    case workEnded(at: Date)
    case sessionEnded(at: Date)
}

struct ObservedSessionSnapshot: Hashable, Sendable {
    let session: ObservedSession
    let claim: LegacySnapshotLifecycleClaim
    let expiresAt: Date?

    init(
        session: ObservedSession,
        claim: LegacySnapshotLifecycleClaim,
        expiresAt: Date? = nil
    ) {
        self.session = session
        self.claim = claim
        self.expiresAt = expiresAt
    }
}

struct EvidenceBatch: Hashable, Sendable {
    enum Mode: Hashable, Sendable {
        case snapshot
        case delta
    }

    static let currentSchemaVersion: UInt = 1

    let schemaVersion: UInt
    let source: SourceID
    let sequence: UInt64
    let mode: Mode
    let observedAt: Date
    let sessions: [ObservedSession]
    let items: [SessionEvidence]

    init(
        schemaVersion: UInt = EvidenceBatch.currentSchemaVersion,
        source: SourceID,
        sequence: UInt64,
        mode: Mode,
        observedAt: Date,
        sessions: [ObservedSession],
        items: [SessionEvidence]
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.sequence = sequence
        self.mode = mode
        self.observedAt = observedAt
        self.sessions = sessions
        self.items = items
    }

    static func legacySnapshot(
        source: ObservationSourceDescriptor,
        sequence: UInt64,
        observedAt: Date,
        sessions: [ObservedSessionSnapshot]
    ) -> EvidenceBatch {
        precondition(
            source.contract == .localSnapshotV1,
            "Legacy snapshot claims require the perch.local-snapshot.v1 contract"
        )
        let metadata = sessions.map(\.session)
        let evidence = sessions.flatMap { snapshot -> [SessionEvidence] in
            let key = snapshot.session.key
            let seenAt = snapshot.session.lastActivity ?? observedAt
            var items = [SessionEvidence(
                id: evidenceID(for: key, suffix: "seen"),
                session: key,
                source: source.id,
                eventAt: seenAt,
                observedAt: observedAt,
                expiresAt: snapshot.expiresAt,
                authority: .presence,
                kind: .sessionSeen
            )]

            let event: (suffix: String, at: Date, kind: EvidenceKind)?
            switch snapshot.claim {
            case .presenceOnly:
                event = nil
            case let .workBegan(at):
                event = ("working", at, .workBegan)
            case let .handoffOpened(token, reason, at):
                event = ("handoff:\(token.rawValue)", at, .handoffOpened(token: token, reason: reason))
            case let .workEnded(at):
                event = ("idle", at, .workEnded)
            case let .sessionEnded(at):
                event = ("done", at, .sessionEnded)
            }

            if let event {
                items.append(SessionEvidence(
                    id: evidenceID(for: key, suffix: event.suffix),
                    session: key,
                    source: source.id,
                    eventAt: event.at,
                    observedAt: observedAt,
                    expiresAt: snapshot.expiresAt,
                    authority: .authoritative,
                    kind: event.kind
                ))
            }
            return items
        }

        return EvidenceBatch(
            source: source.id,
            sequence: sequence,
            mode: .snapshot,
            observedAt: observedAt,
            sessions: metadata,
            items: evidence
        )
    }

    private static func evidenceID(for session: SessionKey, suffix: String) -> EvidenceID {
        EvidenceID(rawValue: [
            session.provider.rawValue,
            session.runtime.rawValue,
            session.value,
            suffix,
        ].joined(separator: "\u{1F}"))
    }
}
