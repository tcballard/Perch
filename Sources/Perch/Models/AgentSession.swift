import Foundation

struct ProviderID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: String

    static let mock = ProviderID(rawValue: "mock")
    static let codex = ProviderID(rawValue: "codex")
    static let claude = ProviderID(rawValue: "claude")
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
    struct ID: Hashable, Sendable {
        let provider: ProviderID
        let value: String
    }

    let provider: ProviderID
    let id: ID
    let label: String?
    let workingDirectory: URL?
    let nativeSurface: NativeSurfaceHandle?
    let state: AgentState
    let waitingOn: String?
    let lastActivity: Date?
    let confidence: StateConfidence
    let validatedProviderVersion: String?
    var waitingSince: Date?

    init(
        provider: ProviderID,
        id: String,
        label: String? = nil,
        workingDirectory: URL? = nil,
        nativeSurface: NativeSurfaceHandle? = nil,
        state: AgentState,
        waitingOn: String? = nil,
        lastActivity: Date? = nil,
        confidence: StateConfidence,
        validatedProviderVersion: String? = nil,
        waitingSince: Date? = nil
    ) {
        self.provider = provider
        self.id = ID(provider: provider, value: id)
        self.label = label
        self.workingDirectory = workingDirectory
        self.nativeSurface = nativeSurface
        self.state = state
        self.waitingOn = waitingOn
        self.lastActivity = lastActivity
        self.confidence = confidence
        self.validatedProviderVersion = validatedProviderVersion
        self.waitingSince = waitingSince
    }
}
