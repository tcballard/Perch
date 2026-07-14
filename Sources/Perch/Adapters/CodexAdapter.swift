import AppKit
import Foundation

actor CodexAdapter: AgentProviderAdapter {
    nonisolated let id = ProviderID.codex
    nonisolated let isEnabled: Bool

    private let homeDirectory: URL
    private let codexExecutable: URL
    private let sqliteExecutable = URL(fileURLWithPath: "/usr/bin/sqlite3")
    private let validatedVersions: Set<String> = ["0.144.0-alpha.4", "0.144.2"]
    private var cachedVersion: (signature: String, value: String)?

    init(
        isEnabled: Bool = true,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexExecutable: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
    ) {
        self.isEnabled = isEnabled
        self.homeDirectory = homeDirectory
        self.codexExecutable = codexExecutable
    }

    func listSessions() async throws -> [AgentSession] {
        let installedVersion = try await installedVersion()
        let rows = try await threadRows()
        let versionMatches = validatedVersions.contains(installedVersion)

        return rows.map { row in
                let parsed = versionMatches
                    ? Self.parseRollout(at: row.rolloutURL)
                    : .unknown
                return AgentSession(
                    provider: id,
                    id: row.id,
                    label: row.cwd.lastPathComponent,
                    workingDirectory: row.cwd,
                    nativeSurface: Self.focusURL(for: row.id).map(NativeSurfaceHandle.url),
                    state: parsed.state,
                    waitingOn: parsed.waitingOn,
                    lastActivity: row.updatedAt,
                    confidence: versionMatches ? parsed.confidence : .unknown,
                    validatedProviderVersion: versionMatches ? installedVersion : nil
                )
        }
    }

    func focus(_ session: AgentSession) async throws {
        guard session.provider == id,
              case let .url(url)? = session.nativeSurface,
              url.scheme == "codex",
              url.host == "threads",
              UUID(uuidString: url.lastPathComponent) != nil else {
            throw AdapterError.invalidSurface
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if !opened { throw AdapterError.focusUnavailable }
    }

    func installedVersion() async throws -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: codexExecutable.path)
        let signature = "\(String(describing: attributes?[.modificationDate])):\(String(describing: attributes?[.size]))"
        if let cachedVersion, cachedVersion.signature == signature { return cachedVersion.value }
        let data = try await BoundedProcess.run(
            executable: codexExecutable,
            arguments: ["--version"],
            outputLimit: 1_024
        )
        let output = String(decoding: data, as: UTF8.self)
        guard let version = output.split(separator: " ").last else {
            throw BoundedProcessError.launchFailed
        }
        let value = String(version).trimmingCharacters(in: .whitespacesAndNewlines)
        cachedVersion = (signature, value)
        return value
    }

    private func threadRows() async throws -> [ThreadRow] {
        let database = homeDirectory.appending(path: ".codex/state_5.sqlite")
        let separator = "\u{1F}"
        let query = """
        SELECT id, cwd, rollout_path, updated_at
        FROM threads
        WHERE archived = 0
          AND updated_at >= CAST(strftime('%s','now') AS INTEGER) - 3600
        ORDER BY updated_at DESC
        LIMIT 50;
        """
        let data = try await BoundedProcess.run(
            executable: sqliteExecutable,
            arguments: ["-readonly", "-separator", separator, database.path, query]
        )
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                let fields = line.split(separator: Character(separator), omittingEmptySubsequences: false)
                guard fields.count == 4,
                      UUID(uuidString: String(fields[0])) != nil,
                      let updated = TimeInterval(fields[3]) else { return nil }
                return ThreadRow(
                    id: String(fields[0]),
                    cwd: URL(fileURLWithPath: String(fields[1])),
                    rolloutURL: URL(fileURLWithPath: String(fields[2])),
                    updatedAt: Date(timeIntervalSince1970: updated)
                )
            }
    }

    static func focusURL(for sessionID: String) -> URL? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        return URL(string: "codex://threads/\(sessionID)")
    }

    static func parseRollout(at url: URL) -> ParsedState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 512_000 ? size - 512_000 : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return .unknown }

        var taskActive = false
        var outstandingInputs = Set<String>()
        var outstandingExecutions = Set<String>()
        var outstandingApprovals = Set<String>()
        var approvalsReviewer: String?

        for line in data.split(separator: 0x0A) {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = envelope["payload"] as? [String: Any] else { continue }
            let type = payload["type"] as? String
            if envelope["type"] as? String == "turn_context" {
                approvalsReviewer = payload["approvals_reviewer"] as? String
            }
            switch type {
            case "task_started": taskActive = true
            case "task_complete": taskActive = false
            case "turn_aborted":
                taskActive = false
                outstandingInputs.removeAll()
                outstandingExecutions.removeAll()
                outstandingApprovals.removeAll()
            case "function_call" where payload["name"] as? String == "request_user_input":
                if let callID = payload["call_id"] as? String { outstandingInputs.insert(callID) }
            case "function_call_output":
                if let callID = payload["call_id"] as? String { outstandingInputs.remove(callID) }
            case "custom_tool_call" where payload["name"] as? String == "exec":
                if let callID = payload["call_id"] as? String {
                    outstandingExecutions.insert(callID)
                    if let input = payload["input"] as? String,
                       let inputData = input.data(using: .utf8),
                       let metadata = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
                       metadata["sandbox_permissions"] as? String == "require_escalated" {
                        outstandingApprovals.insert(callID)
                    }
                }
            case "custom_tool_call_output":
                if let callID = payload["call_id"] as? String {
                    outstandingExecutions.remove(callID)
                    outstandingApprovals.remove(callID)
                }
            default: break
            }
        }

        if !outstandingApprovals.isEmpty ||
            (!outstandingExecutions.isEmpty && approvalsReviewer == "user") {
            return ParsedState(state: .waiting, waitingOn: "permission required", confidence: .observed)
        }
        if !outstandingInputs.isEmpty {
            return ParsedState(state: .waiting, waitingOn: "input required", confidence: .observed)
        }
        if taskActive {
            return ParsedState(state: .working, waitingOn: nil, confidence: .observed)
        }
        return ParsedState(state: .idle, waitingOn: nil, confidence: .observed)
    }
}

extension CodexAdapter {
    struct ParsedState: Equatable {
        let state: AgentState
        let waitingOn: String?
        let confidence: StateConfidence

        static let unknown = ParsedState(state: .unknown, waitingOn: nil, confidence: .unknown)
    }

    private struct ThreadRow {
        let id: String
        let cwd: URL
        let rolloutURL: URL
        let updatedAt: Date
    }
}
