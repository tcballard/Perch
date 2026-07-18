import Foundation

protocol AgentProviderAdapter: Sendable {
    nonisolated var source: ObservationSourceDescriptor { get }
    nonisolated var isEnabled: Bool { get }

    func observations(observedAt: Date) async throws -> EvidenceBatch
    func focus(_ session: AgentSession) async throws
}

enum AdapterError: Error, Equatable {
    case focusUnavailable
    case invalidSurface
}
