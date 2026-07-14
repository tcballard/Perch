import XCTest
@testable import Perch

final class ClaudeDesktopAdapterTests: XCTestCase {
    func testQuestionResumeAndInterrupt() throws {
        let question = entry("assistant", [["type": "tool_use", "name": "AskUserQuestion", "id": "q1"]])
        let waiting = try fixture([entry("user", "start"), question])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: waiting).state, .waiting)

        let resumed = try fixture([entry("user", "start"), question, entry("user", [["type": "tool_result", "tool_use_id": "q1"]]), entry("assistant", [["type": "text", "text": "done"]])])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: resumed).state, .idle)

        let interrupted = try fixture([entry("user", "start"), question, entry("user", [["type": "text", "text": "[Request interrupted by user]"]])])
        XCTAssertEqual(ClaudeDesktopAdapter.parseTranscript(at: interrupted).state, .idle)
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
