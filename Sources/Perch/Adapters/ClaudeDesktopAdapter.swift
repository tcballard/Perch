import Foundation

actor ClaudeDesktopAdapter: AgentProviderAdapter {
    nonisolated let source = ObservationSourceDescriptor.claudeDesktopLocalState
    nonisolated let isEnabled: Bool

    private let home: URL
    private let validatedVersion = "2.1.205"
    private var cachedRegistrations: (directory: URL, signature: String, value: [Registration])?
    private var cachedTranscripts: [URL: (signature: String, value: ParsedTranscript)] = [:]
    private var cachedPermissions: (signature: String, value: [String: PermissionRecord])?
    private var sequence: UInt64 = 0

    init(isEnabled: Bool = true, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.isEnabled = isEnabled
        self.home = home
    }

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        let cutoff = observedAt.addingTimeInterval(-3600)
        let currentRegistrations = registrations().compactMap { registration -> (Registration, Date)? in
            let transcript = transcriptURL(for: registration)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: transcript.path),
                  let modified = attributes[.modificationDate] as? Date,
                  modified >= cutoff else { return nil }
            return (registration, modified)
        }.sorted { $0.1 > $1.1 }.prefix(20).map(\.0)
        let permissionSessions = outstandingPermissionSessions()
        sequence += 1

        let snapshots = currentRegistrations.compactMap { registration -> ObservedSessionSnapshot? in
            let transcript = self.transcriptURL(for: registration)
            guard FileManager.default.fileExists(atPath: transcript.path) else { return nil }
            let parsed = self.transcript(at: transcript)
            let versionMatches = parsed.version == validatedVersion
            let key = SessionKey(
                provider: source.provider,
                runtime: source.runtime,
                value: registration.localID
            )
            let claim: LegacySnapshotLifecycleClaim
            let permissions = permissionSessions[registration.localID] ?? []
            if !versionMatches {
                claim = .presenceOnly
            } else if parsed.isAmbiguous ||
                        permissions.count > 1 ||
                        (!permissions.isEmpty && parsed.state == .waiting) {
                claim = .presenceOnly
            } else if let permission = permissions.first,
                      let openedAt = permission.openedAt {
                claim = .handoffOpened(
                    token: HandoffToken(rawValue: "permission:\(permission.requestID)"),
                    reason: .permission,
                    at: openedAt
                )
            } else if !permissions.isEmpty {
                claim = .presenceOnly
            } else {
                let transitionAt = parsed.transitionAt ?? observedAt
                switch (parsed.state, parsed.attentionReason, parsed.handoffToken) {
                case let (.waiting, reason?, token?) where parsed.transitionAt != nil:
                    claim = .handoffOpened(token: token, reason: reason, at: transitionAt)
                case (.working, _, _) where parsed.transitionAt != nil:
                    claim = .workBegan(at: transitionAt)
                case (.idle, _, _) where parsed.transitionAt != nil:
                    claim = .workEnded(at: transitionAt)
                case (.done, _, _) where parsed.transitionAt != nil:
                    claim = .sessionEnded(at: transitionAt)
                default:
                    claim = .presenceOnly
                }
            }
            return ObservedSessionSnapshot(
                session: ObservedSession(
                    key: key,
                    label: registration.cwd.lastPathComponent,
                    workingDirectory: registration.cwd,
                    lastActivity: parsed.lastActivity,
                    validatedProviderVersion: versionMatches ? parsed.version : nil
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
        throw AdapterError.focusUnavailable
    }

    func registrationCount() -> Int { registrations().count }

    private func registrations() -> [Registration] {
        let root = home.appending(path: "Library/Application Support/Claude/claude-code-sessions")
        if let cachedRegistrations {
            let attributes = try? FileManager.default.attributesOfItem(atPath: cachedRegistrations.directory.path)
            let signature = "\(String(describing: attributes?[.modificationDate])):\(String(describing: attributes?[.size]))"
            if cachedRegistrations.signature == signature { return cachedRegistrations.value }
        }
        let searchRoot = cachedRegistrations?.directory ?? root
        guard let enumerator = FileManager.default.enumerator(at: searchRoot, includingPropertiesForKeys: nil) else { return [] }
        var registryDirectory: URL?
        let value: [Registration] = enumerator.compactMap { item -> Registration? in
            guard let url = item as? URL, url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let localID = object["sessionId"] as? String, localID.hasPrefix("local_"),
                  let cliID = object["cliSessionId"] as? String, UUID(uuidString: cliID) != nil,
                  let cwd = object["cwd"] as? String else { return nil }
            registryDirectory = url.deletingLastPathComponent()
            return Registration(localID: localID, cliID: cliID, cwd: URL(fileURLWithPath: cwd))
        }
        if let registryDirectory {
            let attributes = try? FileManager.default.attributesOfItem(atPath: registryDirectory.path)
            let signature = "\(String(describing: attributes?[.modificationDate])):\(String(describing: attributes?[.size]))"
            cachedRegistrations = (registryDirectory, signature, value)
        }
        return value
    }

    private func transcriptURL(for registration: Registration) -> URL {
        let projectDirectory = registration.cwd.path.replacingOccurrences(of: "/", with: "-")
        return home.appending(path: ".claude/projects/\(projectDirectory)/\(registration.cliID).jsonl")
    }

    private func outstandingPermissionSessions() -> [String: [PermissionHandoff]] {
        let url = home.appending(path: "Library/Logs/Claude/main.log")
        let signature = Self.fileSignature(at: url)
        let outstanding: [String: PermissionRecord]
        if let cachedPermissions, cachedPermissions.signature == signature {
            outstanding = cachedPermissions.value
        } else {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
            guard let data = try? handle.readToEnd() else { return [:] }
            let text = String(decoding: data, as: UTF8.self)
            var parsed: [String: PermissionRecord] = [:]
            for line in text.split(separator: "\n") {
                let value = String(line)
                if let match = value.wholeMatch(of: /.*Emitted tool permission request ([0-9a-f-]+) for ([A-Za-z0-9_-]+) in session (local_[0-9a-f-]+).*/), match.2 != "AskUserQuestion" {
                    parsed[String(match.1)] = PermissionRecord(
                        sessionID: String(match.3),
                        openedAt: Self.logTimestamp(in: value)
                    )
                }
                if let match = value.wholeMatch(of: /.*Received permission response for ([0-9a-f-]+):.*/) {
                    parsed.removeValue(forKey: String(match.1))
                }
            }
            cachedPermissions = (signature, parsed)
            outstanding = parsed
        }

        var sessions: [String: [PermissionHandoff]] = [:]
        for requestID in outstanding.keys.sorted() {
            guard let record = outstanding[requestID] else { continue }
            sessions[record.sessionID, default: []].append(
                PermissionHandoff(requestID: requestID, openedAt: record.openedAt)
            )
        }
        return sessions
    }

    private static func logTimestamp(in line: String) -> Date? {
        let pattern = #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return parseTimestamp(String(line[range]))
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func transcript(at url: URL) -> ParsedTranscript {
        let signature = Self.fileSignature(at: url)
        if let cached = cachedTranscripts[url], cached.signature == signature {
            return cached.value
        }
        let value = Self.parseTranscript(at: url)
        cachedTranscripts[url] = (signature, value)
        return value
    }

    private static func fileSignature(at url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return "\(String(describing: attributes?[.modificationDate])):\(String(describing: attributes?[.size]))"
    }

    static func parseTranscript(at url: URL) -> ParsedTranscript {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 128_000 ? size - 128_000 : 0)
        guard let data = try? handle.readToEnd() else { return .unknown }
        var state = AgentState.unknown
        var questions: [String: PendingQuestion] = [:]
        var ordinaryTools = Set<String>()
        var version: String?
        var lastActivity: Date?
        var lastTransitionAt: Date?
        var invalid = false

        for line in data.split(separator: 0x0A) {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let candidate = envelope["version"] as? String { version = candidate }
            let eventAt = (envelope["timestamp"] as? String).flatMap { timestamp in
                Self.parseTimestamp(timestamp)
            }
            if let eventAt { lastActivity = eventAt }
            guard let message = envelope["message"] as? [String: Any] else { continue }
            let entryType = envelope["type"] as? String
            let content = message["content"]
            if entryType == "user", content is String {
                state = .working
                lastTransitionAt = eventAt ?? lastTransitionAt
            } else if entryType == "user", let items = content as? [[String: Any]] {
                for item in items {
                    if item["type"] as? String == "text", item["text"] as? String == "[Request interrupted by user]" {
                        questions.removeAll()
                        ordinaryTools.removeAll()
                        state = .idle
                        lastTransitionAt = eventAt ?? lastTransitionAt
                        invalid = false
                    } else if item["type"] as? String == "tool_result" {
                        guard let toolID = item["tool_use_id"] as? String else {
                            invalid = true
                            continue
                        }
                        if questions.removeValue(forKey: toolID) == nil,
                           ordinaryTools.remove(toolID) == nil {
                            invalid = true
                        }
                        state = .working
                        lastTransitionAt = eventAt ?? lastTransitionAt
                    }
                }
            } else if entryType == "assistant", let items = content as? [[String: Any]] {
                var sawText = false
                var sawToolUse = false
                for item in items {
                    if item["type"] as? String == "text" { sawText = true }
                    if item["type"] as? String == "tool_use" {
                        sawToolUse = true
                        state = .working
                        lastTransitionAt = eventAt ?? lastTransitionAt
                        guard let toolID = item["id"] as? String else {
                            invalid = true
                            continue
                        }
                        if questions[toolID] != nil || ordinaryTools.contains(toolID) {
                            invalid = true
                        } else if item["name"] as? String == "AskUserQuestion" {
                            questions[toolID] = PendingQuestion(at: eventAt)
                        } else {
                            ordinaryTools.insert(toolID)
                        }
                    }
                }
                if sawText && !sawToolUse && questions.isEmpty && ordinaryTools.isEmpty {
                    state = .idle
                    lastTransitionAt = eventAt ?? lastTransitionAt
                    invalid = false
                }
            }
        }
        if invalid || questions.count > 1 {
            return .unknown(version: version, lastActivity: lastActivity, isAmbiguous: true)
        }
        if let id = questions.keys.first,
           let question = questions[id] {
            guard let openedAt = question.at else {
                return .unknown(version: version, lastActivity: lastActivity, isAmbiguous: true)
            }
            return ParsedTranscript(
                state: .waiting,
                attentionReason: .input,
                handoffToken: HandoffToken(rawValue: "question:\(id)"),
                transitionAt: openedAt,
                version: version,
                lastActivity: lastActivity,
                isAmbiguous: false
            )
        }
        guard state != .unknown, let lastTransitionAt else {
            return .unknown(version: version, lastActivity: lastActivity)
        }
        return ParsedTranscript(
            state: state,
            attentionReason: nil,
            handoffToken: nil,
            transitionAt: lastTransitionAt,
            version: version,
            lastActivity: lastActivity,
            isAmbiguous: false
        )
    }
}

extension ClaudeDesktopAdapter {
    struct ParsedTranscript {
        let state: AgentState
        let attentionReason: AttentionReason?
        let handoffToken: HandoffToken?
        let transitionAt: Date?
        let version: String?
        let lastActivity: Date?
        let isAmbiguous: Bool

        var waitingOn: String? { attentionReason?.displayText }

        static let unknown = ParsedTranscript(
            state: .unknown,
            attentionReason: nil,
            handoffToken: nil,
            transitionAt: nil,
            version: nil,
            lastActivity: nil,
            isAmbiguous: false
        )

        static func unknown(
            version: String?,
            lastActivity: Date?,
            isAmbiguous: Bool = false
        ) -> ParsedTranscript {
            ParsedTranscript(
                state: .unknown,
                attentionReason: nil,
                handoffToken: nil,
                transitionAt: nil,
                version: version,
                lastActivity: lastActivity,
                isAmbiguous: isAmbiguous
            )
        }
    }
    private struct PendingQuestion { let at: Date? }
    private struct PermissionRecord { let sessionID: String; let openedAt: Date? }
    private struct PermissionHandoff { let requestID: String; let openedAt: Date? }
    private struct Registration { let localID: String; let cliID: String; let cwd: URL }
}
