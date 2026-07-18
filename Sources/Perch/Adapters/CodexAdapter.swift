import AppKit
import Foundation

actor CodexAdapter: AgentProviderAdapter {
    nonisolated let source = ObservationSourceDescriptor.codexDesktopLocalState
    nonisolated let isEnabled: Bool

    private let homeDirectory: URL
    private let codexExecutable: URL
    private let sqliteExecutable = URL(fileURLWithPath: "/usr/bin/sqlite3")
    private let validatedVersions: Set<String> = ["0.144.0-alpha.4", "0.144.2", "0.145.0-alpha.18"]
    private var cachedVersion: (signature: String, value: String)?
    private var sequence: UInt64 = 0

    init(
        isEnabled: Bool = true,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexExecutable: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
    ) {
        self.isEnabled = isEnabled
        self.homeDirectory = homeDirectory
        self.codexExecutable = codexExecutable
    }

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        let installedVersion = try await installedVersion()
        let rows = try await threadRows()
        let versionMatches = validatedVersions.contains(installedVersion)
        sequence += 1

        let snapshots = rows.map { row in
            let parsed = versionMatches
                ? Self.parseRollout(at: row.rolloutURL)
                : .unknown
            let key = SessionKey(
                provider: source.provider,
                runtime: source.runtime,
                value: row.id
            )
            let eventAt = parsed.transitionAt ?? row.updatedAt
            let claim: LegacySnapshotLifecycleClaim
            switch (parsed.state, parsed.attentionReason, parsed.handoffToken) {
            case let (.waiting, reason?, token?) where parsed.transitionAt != nil:
                claim = .handoffOpened(token: token, reason: reason, at: eventAt)
            case (.working, _, _) where parsed.transitionAt != nil:
                claim = .workBegan(at: eventAt)
            case (.idle, _, _) where parsed.transitionAt != nil:
                claim = .workEnded(at: eventAt)
            case (.done, _, _) where parsed.transitionAt != nil:
                claim = .sessionEnded(at: eventAt)
            default:
                claim = .presenceOnly
            }
            return ObservedSessionSnapshot(
                session: ObservedSession(
                    key: key,
                    label: row.cwd.lastPathComponent,
                    workingDirectory: row.cwd,
                    nativeSurface: Self.focusURL(for: row.id).map(NativeSurfaceHandle.url),
                    lastActivity: row.updatedAt,
                    validatedProviderVersion: versionMatches ? installedVersion : nil
                ),
                claim: claim,
                expiresAt: observedAt.addingTimeInterval(5)
            )
        }
        return EvidenceBatch.legacySnapshot(
            source: source,
            sequence: sequence,
            observedAt: observedAt,
            sessions: snapshots
        )
    }

    func focus(_ session: AgentSession) async throws {
        guard session.provider == source.provider,
              session.runtime == source.runtime,
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
        var outstandingInputs: [String: PendingTransition] = [:]
        var outstandingExecutions: [String: PendingTransition] = [:]
        var outstandingApprovals: [String: PendingTransition] = [:]
        var approvalsReviewer: String?
        var lastTransitionAt: Date?
        var invalid = false
        for line in data.split(separator: 0x0A) {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = envelope["payload"] as? [String: Any] else { continue }
            let type = payload["type"] as? String
            let eventAt = (envelope["timestamp"] as? String).flatMap { timestamp in
                Self.parseTimestamp(timestamp)
            }
            if envelope["type"] as? String == "turn_context" {
                approvalsReviewer = payload["approvals_reviewer"] as? String
            }
            switch type {
            case "task_started":
                taskActive = true
                lastTransitionAt = eventAt ?? lastTransitionAt
                invalid = false
            case "task_complete":
                taskActive = false
                outstandingInputs.removeAll()
                outstandingExecutions.removeAll()
                outstandingApprovals.removeAll()
                lastTransitionAt = eventAt ?? lastTransitionAt
                invalid = false
            case "turn_aborted":
                taskActive = false
                outstandingInputs.removeAll()
                outstandingExecutions.removeAll()
                outstandingApprovals.removeAll()
                lastTransitionAt = eventAt ?? lastTransitionAt
                invalid = false
            case "function_call" where payload["name"] as? String == "request_user_input":
                if let callID = payload["call_id"] as? String {
                    outstandingInputs[callID] = PendingTransition(at: eventAt)
                }
            case "function_call_output":
                if let callID = payload["call_id"] as? String {
                    if outstandingInputs.removeValue(forKey: callID) != nil {
                        lastTransitionAt = eventAt ?? lastTransitionAt
                    } else if !outstandingInputs.isEmpty ||
                                !outstandingExecutions.isEmpty ||
                                !outstandingApprovals.isEmpty {
                        invalid = true
                    }
                }
            case "custom_tool_call" where payload["name"] as? String == "exec":
                if let callID = payload["call_id"] as? String {
                    let transition = PendingTransition(at: eventAt)
                    outstandingExecutions[callID] = transition
                    if let input = payload["input"] as? String,
                       let inputData = input.data(using: .utf8),
                       let metadata = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
                       metadata["sandbox_permissions"] as? String == "require_escalated" {
                        outstandingApprovals[callID] = transition
                    }
                }
            case "custom_tool_call_output":
                if let callID = payload["call_id"] as? String {
                    let removedExecution = outstandingExecutions.removeValue(forKey: callID)
                    let removedApproval = outstandingApprovals.removeValue(forKey: callID)
                    if removedExecution != nil || removedApproval != nil {
                        lastTransitionAt = eventAt ?? lastTransitionAt
                    } else if !outstandingInputs.isEmpty ||
                                !outstandingExecutions.isEmpty ||
                                !outstandingApprovals.isEmpty {
                        invalid = true
                    }
                }
            default: break
            }
        }

        guard !invalid else { return .unknown }
        let permissionIDs = approvalsReviewer == "user"
            ? Set(outstandingExecutions.keys).union(outstandingApprovals.keys)
            : Set(outstandingApprovals.keys)
        let permissionHandoffs: [(String, AttentionReason, PendingTransition?)] = permissionIDs.map { id in
            (id, AttentionReason.permission, outstandingApprovals[id] ?? outstandingExecutions[id])
        }
        let inputHandoffs: [(String, AttentionReason, PendingTransition?)] = outstandingInputs.map { entry in
            (entry.key, AttentionReason.input, Optional(entry.value))
        }
        let handoffs = permissionHandoffs + inputHandoffs
        guard handoffs.count <= 1 else { return .unknown }
        if let (id, reason, transition) = handoffs.first {
            guard let transition, let openedAt = transition.at else { return .unknown }
            return ParsedState(
                state: .waiting,
                attentionReason: reason,
                handoffToken: HandoffToken(rawValue: "\(reason.rawValue):\(id)"),
                transitionAt: openedAt
            )
        }
        if taskActive, let lastTransitionAt {
            return ParsedState(
                state: .working,
                attentionReason: nil,
                handoffToken: nil,
                transitionAt: lastTransitionAt
            )
        }
        guard let lastTransitionAt else { return .unknown }
        return ParsedState(
            state: .idle,
            attentionReason: nil,
            handoffToken: nil,
            transitionAt: lastTransitionAt
        )
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension CodexAdapter {
    struct ParsedState: Equatable {
        let state: AgentState
        let attentionReason: AttentionReason?
        let handoffToken: HandoffToken?
        let transitionAt: Date?

        var waitingOn: String? { attentionReason?.displayText }

        static let unknown = ParsedState(
            state: .unknown,
            attentionReason: nil,
            handoffToken: nil,
            transitionAt: nil
        )
    }

    private struct PendingTransition { let at: Date? }
    private struct ThreadRow {
        let id: String
        let cwd: URL
        let rolloutURL: URL
        let updatedAt: Date
    }
}
