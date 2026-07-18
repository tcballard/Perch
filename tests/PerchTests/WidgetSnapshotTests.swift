import XCTest
@testable import Perch

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testLargeWidgetQueueIsBoundedWhileCountRemainsExact() {
        let sessions = (0..<5).map { index in
            AgentSession(
                provider: .codex,
                runtime: .codexDesktop,
                id: "wait-\(index)",
                label: "Project \(index)",
                state: .waiting,
                attentionReason: .permission,
                confidence: .observed,
                waitingSince: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: sessions, generatedAt: .now)

        XCTAssertEqual(snapshot.waitingCount, 5)
        XCTAssertEqual(snapshot.waitingHandoffs.count, 3)
        XCTAssertEqual(snapshot.sessions.count, 5)
    }

    func testSnapshotContainsOnlySanitizedPresentationData() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let session = AgentSession(
            provider: .codex,
            runtime: .codexDesktop,
            id: "private-thread-id",
            label: "Perch",
            workingDirectory: URL(fileURLWithPath: "/Users/tom/Secret/Perch"),
            nativeSurface: .url(URL(string: "codex://threads/visible-focus-id")!),
            state: .waiting,
            attentionReason: .permission,
            lastActivity: generatedAt.addingTimeInterval(-10),
            confidence: .observed,
            waitingSince: generatedAt.addingTimeInterval(-30)
        )

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: [session], generatedAt: generatedAt)
        let data = try JSONEncoder().encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(snapshot.waitingCount, 1)
        XCTAssertEqual(snapshot.waitingHandoffs.first?.projectName, "Perch")
        XCTAssertEqual(snapshot.waitingHandoffs.first?.action, "Permission required")
        XCTAssertEqual(snapshot.sessions.first?.projectName, "Perch")
        XCTAssertEqual(snapshot.sessions.first?.state, .waiting)
        XCTAssertEqual(snapshot.sessions.first?.detail, "Permission required")
        XCTAssertFalse(json.contains("/Users/tom/Secret"))
        XCTAssertFalse(json.contains("private-thread-id"))
    }

    func testUnknownAndStaleSessionsNeverBecomeWidgetHandoffs() {
        let sessions = [
            AgentSession(
                provider: .codex,
                runtime: .codexDesktop,
                id: "unknown",
                label: "Unknown",
                state: .waiting,
                attentionReason: .permission,
                confidence: .unknown
            ),
            AgentSession(
                provider: .claude,
                runtime: .claudeDesktop,
                id: "stale",
                label: "Stale",
                state: .waiting,
                attentionReason: .input,
                confidence: .stale
            )
        ]

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: sessions, generatedAt: .now)

        XCTAssertEqual(snapshot.waitingCount, 0)
        XCTAssertEqual(snapshot.uncertainCount, 2)
        XCTAssertTrue(snapshot.waitingHandoffs.isEmpty)
        XCTAssertEqual(snapshot.sessions.map(\.state), [.uncertain, .uncertain])
        XCTAssertEqual(snapshot.dominantState, .uncertain)
    }

    func testSnapshotPublishesSanitizedSummariesForEveryPresentedState() {
        let now = Date(timeIntervalSince1970: 4_000)
        let sessions = [
            AgentSession(provider: .codex, runtime: .codexDesktop, id: "working", label: "Builder", state: .working, lastActivity: now, confidence: .observed),
            AgentSession(provider: .claude, runtime: .claudeDesktop, id: "resting", label: "Reviewer", state: .idle, lastActivity: now.addingTimeInterval(-10), confidence: .observed),
            AgentSession(provider: .codex, runtime: .codexDesktop, id: "unknown", label: "Experiment", state: .unknown, lastActivity: now.addingTimeInterval(-20), confidence: .unknown)
        ]

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: sessions, generatedAt: now)

        XCTAssertEqual(snapshot.sessions.map(\.projectName), ["Builder", "Reviewer", "Experiment"])
        XCTAssertEqual(snapshot.sessions.map(\.state), [.working, .resting, .uncertain])
        XCTAssertEqual(snapshot.sessions.map(\.detail), ["Working", "Resting", "State uncertain"])
    }

    func testPublisherReloadsOnlyForSemanticChangesAndClearsWaiting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        var reloadCount = 0
        let publisher = WidgetSnapshotPublisher(fileURL: fileURL) { reloadCount += 1 }
        let now = Date(timeIntervalSince1970: 2_000)
        let waiting = AgentSession(
            provider: .codex,
            runtime: .codexDesktop,
            id: "thread",
            label: "Perch",
            state: .waiting,
            attentionReason: .permission,
            confidence: .observed,
            waitingSince: now
        )

        publisher.publish(sessions: [waiting], at: now)
        publisher.publish(sessions: [waiting], at: now.addingTimeInterval(1))
        publisher.publish(
            sessions: [AgentSession(provider: .codex, runtime: .codexDesktop, id: "thread", label: "Perch", state: .done, confidence: .observed)],
            at: now.addingTimeInterval(2)
        )

        XCTAssertEqual(reloadCount, 2)
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let finalSnapshot = try decoder.decode(PerchWidgetSnapshot.self, from: data)
        XCTAssertEqual(finalSnapshot.waitingCount, 0)
        XCTAssertTrue(finalSnapshot.waitingHandoffs.isEmpty)
    }
}
