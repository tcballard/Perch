import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class RosterCoordinator {
    private(set) var sessions: [AgentSession] = []
    private(set) var lastRefresh: Date?

    private let adapters: [any AgentProviderAdapter]
    private let pollingInterval: Duration
    private let staleRetention: Duration
    private var pollingTasks: [ProviderID: Task<Void, Never>] = [:]
    private var waitingStartedAt: [AgentSession.ID: Date] = [:]
    private var snapshots: [ProviderID: [AgentSession]] = [:]
    private var lastSuccess: [ProviderID: ContinuousClock.Instant] = [:]
    private let logger = Logger(subsystem: "com.tcballard.perch", category: "Polling")

    init(adapters: [any AgentProviderAdapter], pollingInterval: Duration, staleRetention: Duration = .seconds(15)) {
        self.adapters = adapters
        self.pollingInterval = pollingInterval
        self.staleRetention = staleRetention
    }

    var waitingCount: Int {
        sessions.lazy.filter { $0.state == .waiting }.count
    }

    func start() {
        guard pollingTasks.isEmpty else { return }
        for adapter in adapters where adapter.isEnabled {
            pollingTasks[adapter.id] = Task { [weak self] in
                guard let self else { return }
                let clock = ContinuousClock()
                var deadline = clock.now
                while !Task.isCancelled {
                    await refresh(adapter: adapter)
                    deadline += pollingInterval
                    if deadline < clock.now { deadline = clock.now }
                    try? await clock.sleep(until: deadline)
                }
            }
        }
    }

    func stop() {
        pollingTasks.values.forEach { $0.cancel() }
        pollingTasks.removeAll()
    }

    func refresh(now: Date = .now) async {
        await withTaskGroup(of: Void.self) { group in
            for adapter in adapters where adapter.isEnabled {
                group.addTask { await self.refresh(adapter: adapter, now: now) }
            }
        }
    }

    private func refresh(adapter: any AgentProviderAdapter, now: Date = .now) async {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let result = try await adapter.listSessions()
            snapshots[adapter.id] = result
            lastSuccess[adapter.id] = clock.now
            publish(now: now)
            #if DEBUG
            let duration = started.duration(to: clock.now)
            logger.info("provider=\(adapter.id.rawValue, privacy: .public) duration=\(String(describing: duration), privacy: .public) sessions=\(result.count)")
            if let eventDate = result.filter({ $0.state == .waiting }).compactMap(\.lastActivity).max() {
                let latency = max(0, now.timeIntervalSince(eventDate))
                logger.info("provider=\(adapter.id.rawValue, privacy: .public) waiting_transition_latency_seconds=\(latency, privacy: .public)")
            }
            #endif
        } catch {
            if let success = lastSuccess[adapter.id], success.duration(to: clock.now) <= staleRetention {
                snapshots[adapter.id] = snapshots[adapter.id, default: []].map { session in
                    AgentSession(provider: session.provider, id: session.id.value, label: session.label, workingDirectory: session.workingDirectory, nativeSurface: session.nativeSurface, state: .unknown, lastActivity: session.lastActivity, confidence: .stale, validatedProviderVersion: session.validatedProviderVersion)
                }
            } else {
                snapshots[adapter.id] = []
            }
            publish(now: now)
        }
    }

    private func publish(now: Date) {
        let combined = snapshots.values.flatMap { $0 }
        let liveIDs = Set(combined.map(\.id))
        waitingStartedAt = waitingStartedAt.filter { liveIDs.contains($0.key) }

        sessions = combined.map { session in
            var updated = session
            if session.state == .waiting {
                let startedAt = waitingStartedAt[session.id] ?? now
                waitingStartedAt[session.id] = startedAt
                updated.waitingSince = startedAt
            } else {
                waitingStartedAt.removeValue(forKey: session.id)
                updated.waitingSince = nil
            }
            return updated
        }
        .sorted(by: Self.sortSessions)
        lastRefresh = now
    }

    func focus(_ session: AgentSession) async throws {
        guard let adapter = adapters.first(where: { $0.id == session.provider }) else {
            throw AdapterError.focusUnavailable
        }
        try await adapter.focus(session)
    }

    private static func sortSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.state.sortPriority != rhs.state.sortPriority {
            return lhs.state.sortPriority < rhs.state.sortPriority
        }
        return (lhs.label ?? lhs.id.value).localizedCaseInsensitiveCompare(
            rhs.label ?? rhs.id.value
        ) == .orderedAscending
    }
}
