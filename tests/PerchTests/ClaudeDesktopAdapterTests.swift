import XCTest
@testable import Perch

final class ClaudeDesktopAdapterTests: XCTestCase {
    func testQuestionResumeAndInterrupt() throws {
        let question = entry("assistant", [["type": "tool_use", "name": "AskUserQuestion", "id": "q1"]])
        let waiting = try fixture([entry("user", "start"), question])
        let parsedWaiting = ClaudeDesktopAdapter.parseTranscript(at: waiting)
        XCTAssertEqual(parsedWaiting.state, .waiting)
        XCTAssertEqual(parsedWaiting.attentionReason, .input)
        XCTAssertEqual(parsedWaiting.handoffToken?.rawValue, "question:q1")

        let resumed = try fixture([entry("user", "start"), question, entry("user", [["type": "tool_result", "tool_use_id": "q1"]]), entry("assistant", [["type": "text", "text": "done"]])])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: resumed).state, .idle)
        XCTAssertNil(ClaudeDesktopAdapter.parseTranscript(at: resumed).attentionReason)

        let interrupted = try fixture([entry("user", "start"), question, entry("user", [["type": "text", "text": "[Request interrupted by user]"]])])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: interrupted).state, .idle)
        XCTAssertNil(ClaudeDesktopAdapter.parseTranscript(at: interrupted).attentionReason)
    }

    func testTextAlongsideOrdinaryToolUseRemainsWorking() throws {
        let transcript = try fixture([
            entry("assistant", [
                ["type": "text", "text": "I will check."],
                ["type": "tool_use", "name": "Bash", "id": "tool-1"],
            ]),
        ])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: transcript).state, .working)
    }

    func testUncorrelatedToolResultAndMultipleQuestionsRemainUnknown() throws {
        let orphan = try fixture([
            entry("user", [["type": "tool_result", "tool_use_id": "missing"]]),
        ])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: orphan).state, .unknown)

        let multiple = try fixture([
            entry("assistant", [
                ["type": "tool_use", "name": "AskUserQuestion", "id": "q1"],
                ["type": "tool_use", "name": "AskUserQuestion", "id": "q2"],
            ]),
        ])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: multiple).state, .unknown)
        XCTAssertNil(ClaudeDesktopAdapter.parseTranscript(at: multiple).attentionReason)
    }

    func testTimestampLessQuestionRemainsUnknown() throws {
        var question = entry(
            "assistant",
            [["type": "tool_use", "name": "AskUserQuestion", "id": "q1"]]
        )
        question.removeValue(forKey: "timestamp")
        let transcript = try fixture([question])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: transcript).state, .unknown)
    }

    func testSimultaneousPermissionAndQuestionEvidenceFailsClosed() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let localID = "local_11111111-1111-1111-1111-111111111111"
        let cliID = "11111111-1111-1111-1111-111111111111"
        let registry = home.appending(path: "Library/Application Support/Claude/claude-code-sessions/account/project")
        let transcriptDirectory = home.appending(path: ".claude/projects/-private-tmp-fixture")
        let logDirectory = home.appending(path: "Library/Logs/Claude")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }

        try registration(local: localID, cli: cliID).write(to: registry.appending(path: "session.json"))
        let question = entry(
            "assistant",
            [["type": "tool_use", "name": "AskUserQuestion", "id": "q1"]]
        )
        let transcriptData = try JSONSerialization.data(withJSONObject: question) + Data([0x0A])
        try transcriptData.write(to: transcriptDirectory.appending(path: "\(cliID).jsonl"))
        let log = """
        2026-07-14T00:00:00Z Emitted tool permission request aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa for Bash in session \(localID)
        2026-07-14T00:00:01Z Emitted tool permission request bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb for Write in session \(localID)
        """
        try log.write(to: logDirectory.appending(path: "main.log"), atomically: true, encoding: .utf8)

        let observedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-14T00:00:02Z"))
        let adapter = ClaudeDesktopAdapter(home: home)
        let batch = try await adapter.observations(observedAt: observedAt)
        var reducer = AttentionReducer()
        try reducer.ingest(batch, from: adapter.source, receivedAt: observedAt)

        let session = try XCTUnwrap(reducer.sessions(at: observedAt).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testRegistrationCacheInvalidatesWhenRegistryDirectoryChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let registry = home.appending(path: "Library/Application Support/Claude/claude-code-sessions/account/project")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        try registration(local: "local_11111111-1111-1111-1111-111111111111", cli: "11111111-1111-1111-1111-111111111111").write(to: registry.appending(path: "one.json"))
        let adapter = ClaudeDesktopAdapter(home: home)
        let firstCount = await adapter.registrationCount()
        XCTAssertEqual(firstCount, 1)

        try registration(local: "local_22222222-2222-2222-2222-222222222222", cli: "22222222-2222-2222-2222-222222222222").write(to: registry.appending(path: "two.json"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: registry.path)
        let secondCount = await adapter.registrationCount()
        XCTAssertEqual(secondCount, 2)
    }

    private func registration(local: String, cli: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sessionId": local, "cliSessionId": cli, "cwd": "/private/tmp/fixture"])
    }

    private func entry(_ type: String, _ content: Any) -> [String: Any] {
        ["type": type, "version": "2.1.205", "timestamp": "2026-07-14T00:00:00Z", "message": ["content": content]]
    }

    private func fixture(_ records: [[String: Any]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jsonl")
        let data = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }.reduce(Data(), +)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
