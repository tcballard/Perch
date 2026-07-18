import XCTest
@testable import Perch

final class CodexAdapterTests: XCTestCase {
    func testStructuredInputWaitAndAbort() throws {
        let waiting = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: waiting).state, .waiting)
        XCTAssertEqual(CodexAdapter.parseRollout(at: waiting).attentionReason, .input)
        XCTAssertEqual(CodexAdapter.parseRollout(at: waiting).handoffToken?.rawValue, "input:input-1")

        let aborted = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
            event("turn_aborted"),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: aborted).state, .idle)
        XCTAssertNil(CodexAdapter.parseRollout(at: aborted).attentionReason)
    }

    func testStructuredPermissionWaitAndMatchingOutput() throws {
        let inputData = try JSONSerialization.data(
            withJSONObject: ["sandbox_permissions": "require_escalated"]
        )
        let input = String(decoding: inputData, as: UTF8.self)
        let waiting = try fixture([
            event("task_started"),
            event("custom_tool_call", ["name": "exec", "call_id": "exec-1", "input": input]),
        ])
        let parsed = CodexAdapter.parseRollout(at: waiting)
        XCTAssertEqual(parsed.state, .waiting)
        XCTAssertEqual(parsed.attentionReason, .permission)
        XCTAssertEqual(parsed.handoffToken?.rawValue, "permission:exec-1")

        let resumed = try fixture([
            event("task_started"),
            event("custom_tool_call", ["name": "exec", "call_id": "exec-1", "input": input]),
            event("custom_tool_call_output", ["call_id": "exec-1"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: resumed).state, .working)
        XCTAssertNil(CodexAdapter.parseRollout(at: resumed).attentionReason)
    }

    func testCurrentResponseItemPermissionWrapperAndMatchingOutput() throws {
        let inputData = try JSONSerialization.data(
            withJSONObject: ["sandbox_permissions": "require_escalated"]
        )
        let input = String(decoding: inputData, as: UTF8.self)
        let turnContext: [String: Any] = [
            "timestamp": "2026-07-18T00:00:00Z",
            "type": "turn_context",
            "payload": ["approvals_reviewer": "auto_review"],
        ]
        let permissionCall: [String: Any] = [
            "timestamp": "2026-07-18T00:00:01Z",
            "type": "response_item",
            "payload": [
                "type": "custom_tool_call",
                "name": "exec",
                "call_id": "exec-current",
                "input": input,
            ],
        ]
        let permissionOutput: [String: Any] = [
            "timestamp": "2026-07-18T00:00:02Z",
            "type": "response_item",
            "payload": [
                "type": "custom_tool_call_output",
                "call_id": "exec-current",
            ],
        ]

        let waiting = try fixture([turnContext, event("task_started"), permissionCall])
        let parsed = CodexAdapter.parseRollout(at: waiting)
        XCTAssertEqual(parsed.state, .waiting)
        XCTAssertEqual(parsed.attentionReason, .permission)
        XCTAssertEqual(parsed.handoffToken?.rawValue, "permission:exec-current")

        let resumed = try fixture([turnContext, event("task_started"), permissionCall, permissionOutput])
        XCTAssertEqual(CodexAdapter.parseRollout(at: resumed).state, .working)
        XCTAssertNil(CodexAdapter.parseRollout(at: resumed).attentionReason)
    }

    func testTaskCompletionClearsOutstandingHandoff() throws {
        let completed = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
            event("task_complete"),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: completed).state, .idle)
        XCTAssertNil(CodexAdapter.parseRollout(at: completed).attentionReason)
    }

    func testEmptyAndTimestampLessRolloutsRemainUnknown() throws {
        let empty = try fixture([])
        XCTAssertEqual(CodexAdapter.parseRollout(at: empty).state, .unknown)

        let timestampLess = try fixture([
            ["type": "event_msg", "payload": ["type": "task_started"]],
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: timestampLess).state, .unknown)
    }

    func testMultipleOutstandingHandoffsRemainUnknown() throws {
        let ambiguous = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
            event("function_call", ["name": "request_user_input", "call_id": "input-2"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: ambiguous).state, .unknown)
        XCTAssertNil(CodexAdapter.parseRollout(at: ambiguous).attentionReason)
    }

    func testUncorrelatedOutputsRemainUnknown() throws {
        let orphan = try fixture([
            event("function_call_output", ["call_id": "missing"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: orphan).state, .unknown)

        let conflicting = try fixture([
            event("task_started"),
            event("function_call", ["name": "request_user_input", "call_id": "input-1"]),
            event("function_call_output", ["call_id": "different"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: conflicting).state, .unknown)
        XCTAssertNil(CodexAdapter.parseRollout(at: conflicting).attentionReason)
    }

    func testOrdinaryPromptLikeTextDoesNotCreateWait() throws {
        let url = try fixture([
            event("task_started"),
            event("agent_message", ["message": "Should I proceed? Permission required."]),
            event("task_complete"),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .idle)
    }

    func testExplicitHumanBlockWaitsIndependentOfToolType() throws {
        for name in ["computer_use", "mcp__github__merge_pull_request", "exec_command"] {
            let url = try fixture([
                event("task_started"),
                event("function_call", ["name": name, "call_id": "approval-1", "arguments": "{\"requires_approval\":true}"]),
            ])
            XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .waiting, name)
        }
    }

    func testActiveToolsRemainWorkingWithoutHumanBlock() throws {
        for name in ["computer_use", "mcp__github__get_pull_request", "exec_command"] {
            let url = try fixture([
                event("task_started"),
                event("function_call", ["name": name, "call_id": "active-1", "arguments": "{}"]),
            ])
            XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .working, name)
        }
    }

    func testEscalatedAndNestedInterventionMetadataWaits() throws {
        for arguments in [
            "{\"sandbox_permissions\":\"require_escalated\"}",
            "{\"interaction\":{\"confirmation_status\":\"pending\"}}",
        ] {
            let url = try fixture([
                event("task_started"),
                event("custom_tool_call", ["name": "provider_tool", "call_id": "approval-1", "input": arguments]),
            ])
            XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .waiting)
        }
    }

    func testRealExecWrapperWithEscalationWaits() throws {
        let wrapper = #"const r = await tools.exec_command({cmd:"git push",sandbox_permissions:"require_escalated",justification:"May I push?"}); text(r.output);"#
        let url = try fixture([
            event("task_started"),
            event("custom_tool_call", ["name": "exec", "call_id": "approval-1", "input": wrapper]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .waiting)
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).waitingOn, "permission required")
    }

    func testRealExecWrapperWithoutEscalationIsWorking() throws {
        let wrapper = #"const r = await tools.exec_command({cmd:"git status",yield_time_ms:10000}); text(r.output);"#
        let url = try fixture([
            event("task_started"),
            event("custom_tool_call", ["name": "exec", "call_id": "active-1", "input": wrapper]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .working)
    }

    func testAmbiguousToolMetadataIsUncertainNotUrgent() throws {
        let url = try fixture([
            event("task_started"),
            event("function_call", ["name": "mcp__provider__action", "call_id": "ambiguous-1", "arguments": "{not-json"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .unknown)
        XCTAssertNil(CodexAdapter.parseRollout(at: url).attentionReason)
    }

    func testCompletedHumanBlockReturnsToActiveWork() throws {
        let url = try fixture([
            event("task_started"),
            event("function_call", ["name": "computer_use", "call_id": "approval-1", "arguments": "{\"requires_confirmation\":true}"]),
            event("function_call_output", ["call_id": "approval-1"]),
        ])
        XCTAssertEqual(CodexAdapter.parseRollout(at: url).state, .working)
    }

    func testTaskCompletionClearsOrphanedHumanBlock() throws {
        let url = try fixture([
            event("task_started"),
            event("custom_tool_call", [
                "name": "exec",
                "call_id": "approval-1",
                "input": #"const r = await tools.exec_command({cmd:"true",sandbox_permissions:"require_escalated"});"#,
            ]),
            event("task_complete"),
        ])
        let parsed = CodexAdapter.parseRollout(at: url)
        XCTAssertEqual(parsed.state, .idle)
        XCTAssertNil(parsed.waitingOn)
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
        let adapter = CodexAdapter(homeDirectory: directory, codexExecutable: executable, versionTimeout: 5)
        let firstVersion = try await adapter.installedVersion()
        XCTAssertEqual(firstVersion, "1.0")

        try "#!/bin/sh\necho 'codex-cli 2.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755, .modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: executable.path)
        let secondVersion = try await adapter.installedVersion()
        XCTAssertEqual(secondVersion, "2.0")
    }

    func testObservationsIncludeOnlyVisibleTopLevelUserThreads() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let codexDirectory = directory.appending(path: ".codex")
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appending(path: "codex")
        try "#!/bin/sh\necho 'codex-cli 0.145.0-alpha.18'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let visibleRollout = try fixture([event("task_started")])
        let hiddenRollout = try fixture([event("task_started")])
        let database = codexDirectory.appending(path: "state_5.sqlite")
        let now = Int(Date().timeIntervalSince1970)
        let sql = """
        CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT, updated_at INTEGER, archived INTEGER, preview TEXT, thread_source TEXT);
        INSERT INTO threads VALUES ('019f5ee8-576e-74b3-9b84-a5b73b3ad1d5','/tmp/visible','\(visibleRollout.path)',\(now),0,'Visible task','user');
        INSERT INTO threads VALUES ('019f5ee8-576e-74b3-9b84-a5b73b3ad1d6','/tmp/hidden','\(hiddenRollout.path)',\(now),0,'Hidden helper','subagent');
        """
        _ = try await BoundedProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: [database.path, sql],
            timeout: 5
        )

        let adapter = CodexAdapter(homeDirectory: directory, codexExecutable: executable, versionTimeout: 5)
        let observedAt = Date(timeIntervalSince1970: TimeInterval(now + 1))
        let batch = try await adapter.observations(observedAt: observedAt)
        var reducer = AttentionReducer()
        try reducer.ingest(batch, from: adapter.source, receivedAt: observedAt)
        let sessions = reducer.sessions(at: observedAt)
        XCTAssertEqual(sessions.map(\.id.value), ["019f5ee8-576e-74b3-9b84-a5b73b3ad1d5"])
        XCTAssertEqual(sessions.map(\.state), [AgentState.working])
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
