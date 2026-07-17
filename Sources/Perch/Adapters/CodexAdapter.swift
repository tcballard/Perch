import AppKit
import Foundation

actor CodexAdapter: AgentProviderAdapter {
    nonisolated let id = ProviderID.codex
    nonisolated let isEnabled: Bool

    private let homeDirectory: URL
    private let codexExecutable: URL
    private let versionTimeout: TimeInterval
    private let sqliteExecutable = URL(fileURLWithPath: "/usr/bin/sqlite3")
    private let validatedVersions: Set<String> = ["0.144.0-alpha.4", "0.144.2"]
    private var cachedVersion: (signature: String, value: String)?

    init(
        isEnabled: Bool = true,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexExecutable: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        versionTimeout: TimeInterval = 2
    ) {
        self.isEnabled = isEnabled
        self.homeDirectory = homeDirectory
        self.codexExecutable = codexExecutable
        self.versionTimeout = versionTimeout
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
            timeout: versionTimeout,
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
          AND preview <> ''
          AND thread_source = 'user'
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
        var tools = ToolActivityNormalizer()

        for line in data.split(separator: 0x0A) {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = envelope["payload"] as? [String: Any] else { continue }
            let type = payload["type"] as? String
            switch type {
            case "task_started": taskActive = true
            case "task_complete":
                taskActive = false
                tools.clear()
            case "turn_aborted":
                taskActive = false
                tools.clear()
            case "function_call", "custom_tool_call": tools.started(payload)
            case "function_call_output", "custom_tool_call_output": tools.finished(payload)
            default: break
            }
        }

        if tools.hasHumanBlock { return ParsedState(state: .waiting, waitingOn: tools.waitingReason, confidence: .observed) }
        if tools.hasAmbiguousBlock { return .unknown }
        if tools.hasActiveTool { return ParsedState(state: .working, waitingOn: nil, confidence: .observed) }
        if taskActive {
            return ParsedState(state: .working, waitingOn: nil, confidence: .observed)
        }
        return ParsedState(state: .idle, waitingOn: nil, confidence: .observed)
    }
}

private struct ToolActivityNormalizer {
    private var active = Set<String>()
    private var humanBlocked: [String: String] = [:]
    private var ambiguous = Set<String>()

    var hasActiveTool: Bool { !active.isEmpty }
    var hasHumanBlock: Bool { !humanBlocked.isEmpty }
    var hasAmbiguousBlock: Bool { !ambiguous.isEmpty }
    var waitingReason: String { humanBlocked.values.first ?? "intervention required" }

    mutating func started(_ payload: [String: Any]) {
        guard let callID = payload["call_id"] as? String else { return }
        active.insert(callID)
        if payload["name"] as? String == "request_user_input" {
            humanBlocked[callID] = "input required"
            return
        }
        let arguments = payload["arguments"] as? String
        guard let raw = arguments ?? (payload["input"] as? String) else { return }
        if Self.rawInputRequiresHuman(raw) {
            humanBlocked[callID] = "permission required"
            return
        }
        guard let data = raw.data(using: .utf8),
              let metadata = try? JSONSerialization.jsonObject(with: data) else {
            // Function-call arguments have a JSON contract, so malformed data
            // is ambiguous. Custom tool input may legitimately be provider
            // wrapper source (for example `exec` JavaScript); absent an exact
            // human-block marker it is ordinary active execution.
            if arguments != nil { ambiguous.insert(callID) }
            return
        }
        if Self.requiresHuman(metadata) { humanBlocked[callID] = "permission required" }
    }

    mutating func finished(_ payload: [String: Any]) {
        guard let callID = payload["call_id"] as? String else { return }
        active.remove(callID); humanBlocked.removeValue(forKey: callID); ambiguous.remove(callID)
    }

    mutating func clear() {
        active.removeAll(); humanBlocked.removeAll(); ambiguous.removeAll()
    }

    private static func requiresHuman(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let key = key.lowercased().replacingOccurrences(of: "_", with: "")
                if key == "sandboxpermissions", child as? String == "require_escalated" { return true }
                if ["requiresapproval", "requiresconfirmation", "requiresintervention", "humanapprovalrequired"].contains(key), child as? Bool == true { return true }
                if ["approvalstatus", "confirmationstatus", "interventionstatus"].contains(key),
                   let status = child as? String,
                   ["required", "pending", "waiting", "requested"].contains(status.lowercased()) { return true }
                if requiresHuman(child) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: requiresHuman)
        }
        return false
    }

    private static func rawInputRequiresHuman(_ raw: String) -> Bool {
        let compact = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\\\"", with: "\"")
        let explicitValues = [
            "sandbox_permissions:\"require_escalated\"",
            "\"sandbox_permissions\":\"require_escalated\"",
            "requires_approval:true",
            "\"requires_approval\":true",
            "requires_confirmation:true",
            "\"requires_confirmation\":true",
            "requires_intervention:true",
            "\"requires_intervention\":true",
        ]
        return explicitValues.contains(where: compact.contains)
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
