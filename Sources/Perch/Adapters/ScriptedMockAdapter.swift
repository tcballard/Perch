import Foundation

actor ScriptedMockAdapter: AgentProviderAdapter {
    nonisolated let source = ObservationSourceDescriptor.mockScripted
    nonisolated let isEnabled = true

    private var pollIndex = 0
    private var sequence: UInt64 = 0
    private let sessionCount: Int

    init(sessionCount: Int = 5) {
        self.sessionCount = sessionCount
    }

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        let states: [AgentState] = [.working, .waiting, .working, .done]
        let state = states[min(pollIndex, states.count - 1)]
        pollIndex += 1
        sequence += 1

        let snapshots = (1...sessionCount).map { index in
            let key = SessionKey(
                provider: source.provider,
                runtime: source.runtime,
                value: "mock-\(index)"
            )
            let claim: LegacySnapshotLifecycleClaim
            switch state {
            case .working:
                claim = .workBegan(at: observedAt)
            case .waiting:
                claim = .handoffOpened(
                    token: HandoffToken(rawValue: "choice-\(index)"),
                    reason: .choice,
                    at: observedAt
                )
            case .done:
                claim = .sessionEnded(at: observedAt)
            case .idle:
                claim = .workEnded(at: observedAt)
            case .unknown:
                claim = .presenceOnly
            }
            return ObservedSessionSnapshot(
                session: ObservedSession(
                    key: key,
                    label: "Example task \(index)",
                    lastActivity: observedAt,
                    validatedProviderVersion: "fixture-1"
                ),
                claim: claim
            )
        }
        return EvidenceBatch.legacySnapshot(
            source: source,
            sequence: sequence,
            observedAt: observedAt,
            sessions: snapshots
        )
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }
}
