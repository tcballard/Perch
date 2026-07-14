import Foundation

protocol AgentProviderAdapter: Sendable {
    var id: ProviderID { get }
    var isEnabled: Bool { get }

    func listSessions() async throws -> [AgentSession]
    func focus(_ session: AgentSession) async throws
}

enum AdapterError: Error, Equatable {
    case focusUnavailable
    case invalidSurface
}
