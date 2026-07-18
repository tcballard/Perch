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
    private let widgetSnapshotPublisher: WidgetSnapshotPublisher?
    private var pollingTasks: [SourceID: Task<Void, Never>] = [:]
    private var projectionTask: Task<Void, Never>?
    private var lastSuccess: [SourceID: ContinuousClock.Instant] = [:]
    private var reducer = AttentionReducer()
    private let logger = Logger(subsystem: "com.tcballard.perch", category: "Polling")

    init(
        adapters: [any AgentProviderAdapter],
        pollingInterval: Duration,
        staleRetention: Duration = .seconds(15),
        widgetSnapshotPublisher: WidgetSnapshotPublisher? = nil
    ) {
        let sourceIDs = adapters.map { $0.source.id }
        precondition(Set(sourceIDs).count == sourceIDs.count, "Observation source IDs must be unique")
        self.adapters = adapters
        self.pollingInterval = pollingInterval
        self.staleRetention = staleRetention
        self.widgetSnapshotPublisher = widgetSnapshotPublisher
    }

    var waitingCount: Int {
        sessions.lazy.filter { $0.state == .waiting }.count
    }

    func start() {
        guard pollingTasks.isEmpty, projectionTask == nil else { return }
        for adapter in adapters where adapter.isEnabled {
            pollingTasks[adapter.source.id] = Task { [weak self] in
                let clock = ContinuousClock()
                var deadline = clock.now
                while !Task.isCancelled {
                    let interval: Duration
                    do {
                        guard let coordinator = self else { return }
                        interval = coordinator.pollingInterval
                        await coordinator.refresh(adapter: adapter)
                    }
                    deadline += interval
                    if deadline < clock.now { deadline = clock.now }
                    try? await clock.sleep(until: deadline)
                }
            }
        }
        projectionTask = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                let interval: Duration
                do {
                    guard let coordinator = self else { return }
                    interval = coordinator.pollingInterval
                }
                deadline += interval
                if deadline < clock.now { deadline = clock.now }
                try? await clock.sleep(until: deadline)
                guard !Task.isCancelled else { return }
                self?.sweepHealthAndPublish(now: .now)
            }
        }
    }

    func stop() {
        pollingTasks.values.forEach { $0.cancel() }
        pollingTasks.removeAll()
        projectionTask?.cancel()
        projectionTask = nil
    }

    func refresh(now fixedNow: Date? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for adapter in adapters where adapter.isEnabled {
                group.addTask { await self.refresh(adapter: adapter, fixedNow: fixedNow) }
            }
        }
    }

    private func refresh(adapter: any AgentProviderAdapter, fixedNow: Date? = nil) async {
        let clock = ContinuousClock()
        let started = clock.now
        let observedAt = fixedNow ?? .now
        do {
            let batch = try await adapter.observations(observedAt: observedAt)
            let completedAt = fixedNow ?? .now
            let completedInstant = clock.now
            let result = try reducer.ingest(batch, from: adapter.source, receivedAt: completedAt)
            if result == .accepted {
                lastSuccess[adapter.source.id] = completedInstant
            } else if result == .duplicate,
                      let success = lastSuccess[adapter.source.id],
                      success.duration(to: completedInstant) > staleRetention {
                reducer.markSourceFailed(adapter.source.id)
            }
            publish(now: completedAt)
            #if DEBUG
            let duration = started.duration(to: completedInstant)
            logger.info("source=\(adapter.source.id.rawValue, privacy: .public) duration=\(String(describing: duration), privacy: .public) sessions=\(batch.sessions.count)")
            let handoffDates = batch.items.compactMap { item -> Date? in
                if case .handoffOpened = item.kind { return item.eventAt }
                return nil
            }
            if let eventDate = handoffDates.max() {
                let latency = max(0, completedAt.timeIntervalSince(eventDate))
                logger.info("source=\(adapter.source.id.rawValue, privacy: .public) waiting_transition_latency_seconds=\(latency, privacy: .public)")
            }
            #endif
        } catch {
            let completedAt = fixedNow ?? .now
            let sourceID = adapter.source.id
            if let success = lastSuccess[sourceID], success.duration(to: clock.now) <= staleRetention {
                reducer.markSourceFailed(sourceID)
            } else {
                reducer.removeSource(sourceID)
                lastSuccess.removeValue(forKey: sourceID)
            }
            publish(now: completedAt)
        }
    }

    private func sweepHealthAndPublish(now: Date) {
        let clock = ContinuousClock()
        for adapter in adapters {
            let sourceID = adapter.source.id
            guard let success = lastSuccess[sourceID],
                  success.duration(to: clock.now) > staleRetention else { continue }
            reducer.removeSource(sourceID)
            lastSuccess.removeValue(forKey: sourceID)
        }
        publish(now: now)
    }

    private func publish(now: Date) {
        sessions = reducer.sessions(at: now).sorted(by: Self.sortSessions)
        lastRefresh = now
        widgetSnapshotPublisher?.publish(sessions: sessions, at: now)
    }

    func focus(_ session: AgentSession) async throws {
        guard let adapter = adapters.first(where: {
            $0.source.provider == session.provider &&
                $0.source.runtime == session.runtime &&
                $0.source.capabilities.contains(.focus)
        }) else {
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
