import Foundation

actor ClaudeDesktopAdapter: AgentProviderAdapter {
    nonisolated let id = ProviderID.claude
    nonisolated let isEnabled: Bool

    private let home: URL
    private let validatedVersion = "2.1.205"
    private var cachedRegistrations: (directory: URL, signature: String, value: [Registration])?
    private var cachedTranscripts: [URL: (signature: String, value: ParsedTranscript)] = [:]
    private var cachedPermissions: (signature: String, value: Set<String>)?

    init(isEnabled: Bool = true, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.isEnabled = isEnabled
        self.home = home
    }

    func listSessions() async throws -> [AgentSession] {
        let cutoff = Date().addingTimeInterval(-3600)
        let currentRegistrations = registrations().compactMap { registration -> (Registration, Date)? in
            let transcript = transcriptURL(for: registration)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: transcript.path),
                  let modified = attributes[.modificationDate] as? Date,
                  modified >= cutoff else { return nil }
            return (registration, modified)
        }.sorted { $0.1 > $1.1 }.prefix(20).map(\.0)
        let permissionSessions = outstandingPermissionSessions()

        return currentRegistrations.compactMap { registration in
                let transcript = self.transcriptURL(for: registration)
                guard FileManager.default.fileExists(atPath: transcript.path) else { return nil }
                let parsed = self.transcript(at: transcript)
                let versionMatches = parsed.version == validatedVersion
                let state: AgentState
                let waitingOn: String?
                if !versionMatches {
                    state = .unknown
                    waitingOn = nil
                } else if permissionSessions.contains(registration.localID) {
                    state = .waiting
                    waitingOn = "permission required"
                } else {
                    state = parsed.state
                    waitingOn = parsed.waitingOn
                }
                return AgentSession(
                    provider: self.id,
                    id: registration.localID,
                    label: registration.cwd.lastPathComponent,
                    workingDirectory: registration.cwd,
                    state: state,
                    waitingOn: waitingOn,
                    lastActivity: parsed.lastActivity,
                    confidence: versionMatches ? .observed : .unknown,
                    validatedProviderVersion: versionMatches ? parsed.version : nil
                )
            }
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

    private func outstandingPermissionSessions() -> Set<String> {
        let url = home.appending(path: "Library/Logs/Claude/main.log")
        let signature = Self.fileSignature(at: url)
        if let cachedPermissions, cachedPermissions.signature == signature {
            return cachedPermissions.value
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
        guard let data = try? handle.readToEnd() else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var outstanding: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let value = String(line)
            if let match = value.wholeMatch(of: /.*Emitted tool permission request ([0-9a-f-]+) for ([A-Za-z0-9_-]+) in session (local_[0-9a-f-]+).*/), match.2 != "AskUserQuestion" {
                outstanding[String(match.1)] = String(match.3)
            }
            if let match = value.wholeMatch(of: /.*Received permission response for ([0-9a-f-]+):.*/) {
                outstanding.removeValue(forKey: String(match.1))
            }
        }
        let value = Set(outstanding.values)
        cachedPermissions = (signature, value)
        return value
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
        var questions = Set<String>()
        var version: String?
        var lastActivity: Date?

        let dateFormatter = ISO8601DateFormatter()
        for line in data.split(separator: 0x0A) {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let candidate = envelope["version"] as? String { version = candidate }
            if let timestamp = envelope["timestamp"] as? String { lastActivity = dateFormatter.date(from: timestamp) }
            guard let message = envelope["message"] as? [String: Any] else { continue }
            let entryType = envelope["type"] as? String
            let content = message["content"]
            if entryType == "user", content is String {
                state = .working
            } else if entryType == "user", let items = content as? [[String: Any]] {
                for item in items {
                    if item["type"] as? String == "text", item["text"] as? String == "[Request interrupted by user]" {
                        questions.removeAll(); state = .idle
                    } else if item["type"] as? String == "tool_result" {
                        if let toolID = item["tool_use_id"] as? String { questions.remove(toolID) }
                        state = .working
                    }
                }
            } else if entryType == "assistant", let items = content as? [[String: Any]] {
                var sawText = false
                for item in items {
                    if item["type"] as? String == "text" { sawText = true }
                    if item["type"] as? String == "tool_use" {
                        state = .working
                        if item["name"] as? String == "AskUserQuestion", let toolID = item["id"] as? String { questions.insert(toolID) }
                    }
                }
                if sawText && questions.isEmpty { state = .idle }
            }
        }
        if !questions.isEmpty { state = .waiting }
        return ParsedTranscript(state: state, waitingOn: state == .waiting ? "input required" : nil, version: version, lastActivity: lastActivity)
    }
}

extension ClaudeDesktopAdapter {
    struct ParsedTranscript {
        let state: AgentState
        let waitingOn: String?
        let version: String?
        let lastActivity: Date?
        static let unknown = ParsedTranscript(state: .unknown, waitingOn: nil, version: nil, lastActivity: nil)
    }
    private struct Registration { let localID: String; let cliID: String; let cwd: URL }
}
