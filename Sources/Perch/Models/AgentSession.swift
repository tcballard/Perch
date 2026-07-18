import Foundation

struct ProviderID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: String

    static let mock = ProviderID(rawValue: "mock")
    static let codex = ProviderID(rawValue: "codex")
    static let claude = ProviderID(rawValue: "claude")
}

struct RuntimeSurfaceID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: String

    static let mockFixture = RuntimeSurfaceID(rawValue: "mock.fixture")
    static let codexDesktop = RuntimeSurfaceID(rawValue: "codex.desktop")
    static let claudeDesktop = RuntimeSurfaceID(rawValue: "claude.desktop")
}

struct SourceID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: String

    static let mockScripted = SourceID(rawValue: "mock.scripted")
    static let codexDesktopLocalState = SourceID(rawValue: "codex.desktop.local-state")
    static let claudeDesktopLocalState = SourceID(rawValue: "claude.desktop.local-state")
}

struct SessionKey: Hashable, Sendable, Codable {
    let provider: ProviderID
    let runtime: RuntimeSurfaceID
    let value: String
}

enum AttentionReason: String, Hashable, Sendable, Codable {
    case input
    case permission
    case choice
    case review

    var displayText: String {
        switch self {
        case .input: return "input required"
        case .permission: return "permission required"
        case .choice: return "choice required"
        case .review: return "review required"
        }
    }
}

enum AgentState: String, Sendable, Codable {
    case working
    case waiting
    case idle
    case done
    case unknown

    var sortPriority: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .idle: 2
        case .done: 3
        case .unknown: 4
        }
    }
}

enum StateConfidence: String, Sendable, Codable {
    case observed
    case inferred
    case stale
    case unknown
}

enum NativeSurfaceHandle: Hashable, Sendable {
    case url(URL)
}

struct AgentSession: Identifiable, Hashable, Sendable {
    typealias ID = SessionKey

    let provider: ProviderID
    let runtime: RuntimeSurfaceID
    let id: ID
    let label: String?
    let workingDirectory: URL?
    let nativeSurface: NativeSurfaceHandle?
    let state: AgentState
    let attentionReason: AttentionReason?
    let lastActivity: Date?
    let confidence: StateConfidence
    let validatedProviderVersion: String?
    var waitingSince: Date?

    var waitingOn: String? { attentionReason?.displayText }

    init(
        provider: ProviderID,
        runtime: RuntimeSurfaceID,
        id: String,
        label: String? = nil,
        workingDirectory: URL? = nil,
        nativeSurface: NativeSurfaceHandle? = nil,
        state: AgentState,
        attentionReason: AttentionReason? = nil,
        lastActivity: Date? = nil,
        confidence: StateConfidence,
        validatedProviderVersion: String? = nil,
        waitingSince: Date? = nil
    ) {
        self.provider = provider
        self.runtime = runtime
        self.id = ID(provider: provider, runtime: runtime, value: id)
        self.label = label
        self.workingDirectory = workingDirectory
        self.nativeSurface = nativeSurface
        self.lastActivity = lastActivity
        self.validatedProviderVersion = validatedProviderVersion

        if state == .waiting, confidence == .observed, let attentionReason {
            self.state = .waiting
            self.attentionReason = attentionReason
            self.confidence = .observed
            self.waitingSince = waitingSince
        } else if state == .waiting {
            self.state = .unknown
            self.attentionReason = nil
            self.confidence = .unknown
            self.waitingSince = nil
        } else {
            self.state = state
            self.attentionReason = nil
            self.confidence = confidence
            self.waitingSince = nil
        }
    }
}
