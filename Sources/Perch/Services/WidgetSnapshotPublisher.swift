import Foundation
import OSLog
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    private let fileURL: URL?
    private let reloadTimelines: () -> Void
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "com.tcballard.perch", category: "WidgetSnapshot")
    private var lastContent: PerchWidgetSnapshot.Content?
    private var lastWrite: Date?
    private var lastFailureLog: Date?

    init(
        fileURL: URL? = PerchWidgetSnapshotStorage.fileURL(),
        reloadTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: PerchWidgetSnapshotStorage.widgetKind)
        }
    ) {
        self.fileURL = fileURL
        self.reloadTimelines = reloadTimelines
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func publish(sessions: [AgentSession], at date: Date) {
        guard let fileURL else {
            logFailure("App Group container is unavailable", at: date)
            return
        }

        let snapshot = Self.makeSnapshot(sessions: sessions, generatedAt: date)
        let contentChanged = snapshot.content != lastContent
        let heartbeatDue = lastWrite.map { date.timeIntervalSince($0) >= 60 } ?? true
        guard contentChanged || heartbeatDue else { return }

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            lastContent = snapshot.content
            lastWrite = date
            lastFailureLog = nil
            if contentChanged {
                reloadTimelines()
            }
        } catch {
            logFailure(
                "Unable to publish widget snapshot: \(error.localizedDescription)",
                at: date
            )
        }
    }

    private func logFailure(_ message: String, at date: Date) {
        let shouldLog = lastFailureLog.map { date.timeIntervalSince($0) >= 60 } ?? true
        guard shouldLog else { return }
        lastFailureLog = date
        logger.error("\(message, privacy: .public)")
    }

    static func makeSnapshot(sessions: [AgentSession], generatedAt: Date) -> PerchWidgetSnapshot {
        let presentation = AttentionPresentation(sessions: sessions)
        let waiting = presentation.waitingSessions.prefix(3).map { item in
            PerchWidgetSnapshot.WaitingHandoff(
                projectName: item.projectName,
                action: item.waitingAction?.rawValue ?? WaitingAction.input.rawValue,
                waitingSince: item.session.waitingSince ?? item.session.lastActivity ?? generatedAt,
                providerName: item.providerName,
                focusURL: item.session.nativeSurface.flatMap { handle in
                    guard case let .url(url) = handle else { return nil }
                    return PerchFocusDeepLink.widgetURL(for: url)
                }
            )
        }

        let summaries = presentation.allSessions
            .sorted { lhs, rhs in
                if lhs.presentedState.sortPriority != rhs.presentedState.sortPriority {
                    return lhs.presentedState.sortPriority < rhs.presentedState.sortPriority
                }
                return (lhs.session.lastActivity ?? .distantPast) > (rhs.session.lastActivity ?? .distantPast)
            }
            .prefix(20)
            .map { item in
                PerchWidgetSnapshot.SessionSummary(
                    projectName: item.projectName,
                    state: PerchWidgetSnapshot.State(item.presentedState),
                    detail: Self.detail(for: item),
                    providerName: item.providerName,
                    activityAt: item.session.waitingSince ?? item.session.lastActivity,
                    focusURL: item.session.nativeSurface.flatMap { handle in
                        guard case let .url(url) = handle else { return nil }
                        return PerchFocusDeepLink.widgetURL(for: url)
                    }
                )
            }

        return PerchWidgetSnapshot(
            generatedAt: generatedAt,
            dominantState: PerchWidgetSnapshot.State(presentation.dominantState),
            waitingCount: presentation.waitingCount,
            workingCount: presentation.workingCount,
            restingCount: presentation.restingCount,
            uncertainCount: presentation.uncertainCount,
            waitingHandoffs: waiting,
            sessions: Array(summaries)
        )
    }

    private static func detail(for item: SessionPresentation) -> String {
        switch item.presentedState {
        case .waiting: return item.waitingAction?.rawValue ?? "Attention required"
        case .working: return "Working"
        case .idle, .done: return "Resting"
        case .unknown: return "State uncertain"
        }
    }
}

private extension PerchWidgetSnapshot.State {
    init(_ state: AgentState) {
        switch state {
        case .waiting: self = .waiting
        case .working: self = .working
        case .idle, .done: self = .resting
        case .unknown: self = .uncertain
        }
    }
}
