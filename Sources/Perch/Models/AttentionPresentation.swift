import Foundation

enum PanelMode: String, CaseIterable, Identifiable {
    case attention = "Attention"
    case allActivity = "All Activity"

    var id: Self { self }
}

enum WaitingAction: String, Sendable {
    case input = "Input required"
    case permission = "Permission required"
    case choice = "Choice required"
    case review = "Review required"

    init(waitingOn: String?) {
        let normalized = waitingOn?.lowercased() ?? ""
        if normalized.contains("permission") || normalized.contains("approval") {
            self = .permission
        } else if normalized.contains("choice") || normalized.contains("select") {
            self = .choice
        } else if normalized.contains("review") {
            self = .review
        } else {
            self = .input
        }
    }
}

struct SessionPresentation: Identifiable, Sendable {
    let session: AgentSession
    let projectName: String
    let providerName: String
    let waitingAction: WaitingAction?

    var id: AgentSession.ID { session.id }
    var canFocus: Bool { session.nativeSurface != nil }
    var isUncertain: Bool { session.state == .unknown || session.confidence == .stale || session.confidence == .unknown }

    init(session: AgentSession) {
        self.session = session
        projectName = Self.projectName(for: session)
        providerName = session.provider.rawValue.capitalized
        waitingAction = session.state == .waiting ? WaitingAction(waitingOn: session.waitingOn) : nil
    }

    private static func projectName(for session: AgentSession) -> String {
        let candidate = session.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = session.workingDirectory?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = [candidate, directory].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Untitled project"
        return String(value.prefix(30))
    }
}

struct AttentionPresentation: Sendable {
    let allSessions: [SessionPresentation]
    let waitingSessions: [SessionPresentation]

    init(sessions: [AgentSession]) {
        allSessions = sessions.map(SessionPresentation.init)
        waitingSessions = allSessions.filter { $0.session.state == .waiting }
    }

    var observedCount: Int { allSessions.count }
    var waitingCount: Int { waitingSessions.count }
    var workingCount: Int { allSessions.filter { $0.session.state == .working }.count }
    var restingCount: Int { allSessions.filter { $0.session.state == .idle || $0.session.state == .done }.count }
    var uncertainCount: Int { allSessions.filter(\.isUncertain).count }
    var usesAggregatedOverview: Bool { observedCount >= 8 }
}
