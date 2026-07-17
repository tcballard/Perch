import XCTest
@testable import Perch

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testLargeWidgetQueueIsBoundedWhileCountRemainsExact() {
        let sessions = (0..<5).map { index in
            AgentSession(
                provider: .codex,
                id: "wait-\(index)",
                label: "Project \(index)",
                state: .waiting,
                waitingOn: "approval",
                confidence: .observed,
                waitingSince: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: sessions, generatedAt: .now)

        XCTAssertEqual(snapshot.waitingCount, 5)
        XCTAssertEqual(snapshot.waitingHandoffs.count, 3)
    }

    func testSnapshotContainsOnlySanitizedPresentationData() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let session = AgentSession(
            provider: .codex,
            id: "private-thread-id",
            label: "Perch",
            workingDirectory: URL(fileURLWithPath: "/Users/tom/Secret/Perch"),
            nativeSurface: .url(URL(string: "codex://threads/visible-focus-id")!),
            state: .waiting,
            waitingOn: "approval",
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
        XCTAssertFalse(json.contains("/Users/tom/Secret"))
        XCTAssertFalse(json.contains("private-thread-id"))
    }

    func testUnknownAndStaleSessionsNeverBecomeWidgetHandoffs() {
        let sessions = [
            AgentSession(
                provider: .codex,
                id: "unknown",
                label: "Unknown",
                state: .waiting,
                waitingOn: "approval",
                confidence: .unknown
            ),
            AgentSession(
                provider: .claude,
                id: "stale",
                label: "Stale",
                state: .waiting,
                waitingOn: "input",
                confidence: .stale
            )
        ]

        let snapshot = WidgetSnapshotPublisher.makeSnapshot(sessions: sessions, generatedAt: .now)

        XCTAssertEqual(snapshot.waitingCount, 0)
        XCTAssertEqual(snapshot.uncertainCount, 2)
        XCTAssertTrue(snapshot.waitingHandoffs.isEmpty)
        XCTAssertEqual(snapshot.dominantState, .uncertain)
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
            id: "thread",
            label: "Perch",
            state: .waiting,
            waitingOn: "approval",
            confidence: .observed,
            waitingSince: now
        )

        publisher.publish(sessions: [waiting], at: now)
        publisher.publish(sessions: [waiting], at: now.addingTimeInterval(1))
        publisher.publish(
            sessions: [AgentSession(provider: .codex, id: "thread", label: "Perch", state: .done, confidence: .observed)],
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
