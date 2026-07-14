import Foundation

actor ScriptedMockAdapter: AgentProviderAdapter {
    nonisolated let id = ProviderID.mock
    nonisolated let isEnabled = true

    private var pollIndex = 0
    private let sessionCount: Int

    init(sessionCount: Int = 5) {
        self.sessionCount = sessionCount
    }

    func listSessions() async throws -> [AgentSession] {
        let states: [AgentState] = [.working, .waiting, .working, .done]
        let state = states[min(pollIndex, states.count - 1)]
        pollIndex += 1

        return (1...sessionCount).map { index in
            AgentSession(
                provider: id,
                id: "mock-\(index)",
                label: "Example task \(index)",
                state: state,
                waitingOn: state == .waiting ? "choice required" : nil,
                lastActivity: .now,
                confidence: .observed,
                validatedProviderVersion: "fixture-1"
            )
        }
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }
}
