import XCTest
@testable import Perch

final class RosterCoordinatorTests: XCTestCase {
    @MainActor
    func testFiveSessionsFollowEveryMockTransition() async {
        let adapter = ScriptedMockAdapter(sessionCount: 5)
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(roster.sessions.map(\.state), Array(repeating: .working, count: 5))
        XCTAssertEqual(roster.waitingCount, 0)

        await roster.refresh(now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(roster.sessions.map(\.state), Array(repeating: .waiting, count: 5))
        XCTAssertEqual(roster.waitingCount, 5)
        XCTAssertTrue(roster.sessions.allSatisfy { $0.waitingSince == Date(timeIntervalSince1970: 2) })

        await roster.refresh(now: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(roster.sessions.map(\.state), Array(repeating: .working, count: 5))
        XCTAssertEqual(roster.waitingCount, 0)

        await roster.refresh(now: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(roster.sessions.map(\.state), Array(repeating: .done, count: 5))
    }

    @MainActor
    func testWaitingSessionsSortBeforeWorkingSessions() async {
        let adapter = FixedAdapter(sessions: [
            AgentSession(provider: .mock, id: "working", label: "A", state: .working, confidence: .observed),
            AgentSession(provider: .mock, id: "waiting", label: "Z", state: .waiting, confidence: .observed),
        ])
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh(now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(roster.sessions.map(\.state), [.waiting, .working])
        XCTAssertEqual(roster.sessions.first?.waitingSince, Date(timeIntervalSince1970: 10))
    }

    @MainActor
    func testFastAdapterPublishesWithoutWaitingForSlowAdapter() async throws {
        let fast = FixedAdapter(sessions: [AgentSession(provider: .mock, id: "fast", state: .working, confidence: .observed)])
        let slow = DelayedAdapter(id: ProviderID(rawValue: "slow"), delay: .seconds(5))
        let roster = RosterCoordinator(adapters: [fast, slow], pollingInterval: .seconds(1))

        roster.start()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(roster.sessions.map(\.id.value), ["fast"])
        roster.stop()
    }

    @MainActor
    func testFailureClearsWaitingAndMarksSnapshotStale() async {
        let adapter = FailingAfterFirstAdapter()
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh()
        XCTAssertEqual(roster.waitingCount, 1)
        await roster.refresh()

        XCTAssertEqual(roster.waitingCount, 0)
        XCTAssertEqual(roster.sessions.first?.state, .unknown)
        XCTAssertEqual(roster.sessions.first?.confidence, .stale)
    }
}

private struct FixedAdapter: AgentProviderAdapter {
    let id = ProviderID.mock
    let isEnabled = true
    let sessions: [AgentSession]

    func listSessions() async throws -> [AgentSession] { sessions }
    func focus(_ session: AgentSession) async throws { throw AdapterError.focusUnavailable }
}

private struct DelayedAdapter: AgentProviderAdapter {
    let id: ProviderID
    let isEnabled = true
    let delay: Duration
    func listSessions() async throws -> [AgentSession] {
        try await Task.sleep(for: delay)
        return []
    }
    func focus(_ session: AgentSession) async throws { throw AdapterError.focusUnavailable }
}

private actor FailingAfterFirstAdapter: AgentProviderAdapter {
    nonisolated let id = ProviderID(rawValue: "failing")
    nonisolated let isEnabled = true
    private var calls = 0
    func listSessions() async throws -> [AgentSession] {
        calls += 1
        if calls > 1 { throw TestError.failed }
        return [AgentSession(provider: id, id: "waiting", state: .waiting, confidence: .observed)]
    }
    func focus(_ session: AgentSession) async throws { throw AdapterError.focusUnavailable }
    enum TestError: Error { case failed }
}
