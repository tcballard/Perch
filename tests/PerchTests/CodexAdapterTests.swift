import XCTest
@testable import Perch

final class CodexAdapterTests: XCTestCase {
    func testStructuredInputWaitAndAbort() throws {
        let waiting = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: waiting).state, .waiting)
        XCTAssertEqual(CodexAdapter.parseRollout(at: waiting).waitingOn, "input required")

        let aborted = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
            event("turn_aborted"),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: aborted).state, .idle)
    }

    func testOrdinaryPromptLikeTextDoesNotCreateWait() throws {
        let url = try fixture([
            event("task_started"),
            event("agent_message", ["message": "Should I proceed? Permission required."]),
            event("task_complete"),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .idle)
    }

    func testFocusURLRejectsUntrustedIDs() {
        XCTAssertNil(CodexAdapter.focusURL(for: "$(open https://example.com)"))
        XCTAssertNotNil(CodexAdapter.focusURL(for: "019f5ee8-576e-74b3-9b84-a5b73b3ad1d5"))
    }

    func testVersionCacheInvalidatesWhenExecutableChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "codex")
        try "#!/bin/sh\necho 'codex-cli 1.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let adapter = CodexAdapter(homeDirectory: directory, codexExecutable: executable)
        let firstVersion = try await adapter.installedVersion()
        XCTAssertEqual(firstVersion, "1.0")

        try "#!/bin/sh\necho 'codex-cli 2.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755, .modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: executable.path)
        let secondVersion = try await adapter.installedVersion()
        XCTAssertEqual(secondVersion, "2.0")
    }

    private func event(_ type: String, _ values: [String: Any] = [:]) -> [String: Any] {
        ["timestamp": "2026-07-14T00:00:00Z", "type": "event_msg", "payload": ["type": type].merging(values) { _, new in new }]
    }

    private func fixture(_ records: [[String: Any]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jsonl")
        let data = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }.reduce(Data(), +)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
