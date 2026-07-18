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

    init(reason: AttentionReason) {
        switch reason {
        case .input: self = .input
        case .permission: self = .permission
        case .choice: self = .choice
        case .review: self = .review
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
    var presentedState: AgentState { isUncertain ? .unknown : session.state }

    init(session: AgentSession) {
        self.session = session
        projectName = Self.projectName(for: session)
        providerName = session.provider.rawValue.capitalized
        let isUncertain = session.state == .unknown || session.confidence == .stale || session.confidence == .unknown
        waitingAction = !isUncertain && session.state == .waiting
            ? session.attentionReason.map(WaitingAction.init(reason:))
            : nil
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
        waitingSessions = allSessions.filter { $0.presentedState == .waiting }
    }

    var observedCount: Int { allSessions.count }
    var waitingCount: Int { waitingSessions.count }
    var workingCount: Int { allSessions.filter { $0.presentedState == .working }.count }
    var restingCount: Int { allSessions.filter { $0.presentedState == .idle || $0.presentedState == .done }.count }
    var uncertainCount: Int { allSessions.filter { $0.presentedState == .unknown }.count }
    var usesAggregatedOverview: Bool { observedCount >= 8 }

    var dominantState: AgentState {
        if waitingCount > 0 { return .waiting }
        if workingCount > 0 { return .working }
        if restingCount > 0 { return .idle }
        return .unknown
    }
}
