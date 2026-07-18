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
        XCTAssertTrue(roster.sessions.allSatisfy { $0.attentionReason == .choice })
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
        let adapter = FixedAdapter(source: .mockScripted, fixtures: [
            Fixture(id: "working", label: "A", state: .working),
            Fixture(id: "waiting", label: "Z", state: .waiting(.choice)),
        ])
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh(now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(roster.sessions.map(\.state), [.waiting, .working])
        XCTAssertEqual(roster.sessions.first?.waitingSince, Date(timeIntervalSince1970: 10))
    }

    @MainActor
    func testFastAdapterPublishesWithoutWaitingForSlowAdapter() async throws {
        let fast = FixedAdapter(
            source: .mockScripted,
            fixtures: [Fixture(id: "fast", state: .working)]
        )
        let slowSource = descriptor(
            source: SourceID(rawValue: "mock.slow"),
            provider: .mock,
            runtime: RuntimeSurfaceID(rawValue: "mock.slow")
        )
        let slow = DelayedAdapter(source: slowSource, delay: .seconds(5))
        let roster = RosterCoordinator(adapters: [fast, slow], pollingInterval: .seconds(1))

        roster.start()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(roster.sessions.map(\.id.value), ["fast"])
        roster.stop()
    }

    @MainActor
    func testSlowPollCannotPublishEvidenceThatExpiredWhileAwaiting() async {
        let source = descriptor(
            source: SourceID(rawValue: "mock.expiring"),
            provider: .mock,
            runtime: RuntimeSurfaceID(rawValue: "mock.expiring")
        )
        let adapter = DelayedExpiringWaitAdapter(source: source)
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh()

        XCTAssertEqual(roster.sessions.first?.state, .unknown)
        XCTAssertEqual(roster.waitingCount, 0)
    }

    @MainActor
    func testFailureClearsWaitingAndMarksSnapshotStale() async {
        let adapter = FailingAfterFirstAdapter()
        let roster = RosterCoordinator(adapters: [adapter], pollingInterval: .seconds(60))

        await roster.refresh(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(roster.waitingCount, 1)
        await roster.refresh(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(roster.waitingCount, 0)
        XCTAssertEqual(roster.sessions.first?.state, .unknown)
        XCTAssertEqual(roster.sessions.first?.confidence, .stale)
        XCTAssertNil(roster.sessions.first?.attentionReason)
    }

    @MainActor
    func testSameProviderSourcesDoNotOverwriteEachOther() async {
        let desktopSource = descriptor(
            source: SourceID(rawValue: "codex.desktop.fixture"),
            provider: .codex,
            runtime: .codexDesktop
        )
        let cliSource = descriptor(
            source: SourceID(rawValue: "codex.cli.fixture"),
            provider: .codex,
            runtime: RuntimeSurfaceID(rawValue: "codex.cli")
        )
        let roster = RosterCoordinator(
            adapters: [
                FixedAdapter(source: desktopSource, fixtures: [Fixture(id: "same-id", state: .working)]),
                FixedAdapter(source: cliSource, fixtures: [Fixture(id: "same-id", state: .idle)]),
            ],
            pollingInterval: .seconds(60)
        )

        await roster.refresh(now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(roster.sessions.count, 2)
        XCTAssertEqual(Set(roster.sessions.map(\.id)).count, 2)
        XCTAssertEqual(Set(roster.sessions.map(\.runtime)), Set([desktopSource.runtime, cliSource.runtime]))
    }
}

private enum FixtureState: Sendable {
    case working
    case waiting(AttentionReason)
    case idle
    case done
    case unknown
}

private struct Fixture: Sendable {
    let id: String
    let label: String?
    let state: FixtureState

    init(id: String, label: String? = nil, state: FixtureState) {
        self.id = id
        self.label = label
        self.state = state
    }
}

private struct FixedAdapter: AgentProviderAdapter {
    let source: ObservationSourceDescriptor
    let isEnabled = true
    let fixtures: [Fixture]

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        fixtureBatch(source: source, sequence: 1, observedAt: observedAt, fixtures: fixtures)
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }
}

private struct DelayedAdapter: AgentProviderAdapter {
    let source: ObservationSourceDescriptor
    let isEnabled = true
    let delay: Duration

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        try await Task.sleep(for: delay)
        return EvidenceBatch.legacySnapshot(
            source: source,
            sequence: 1,
            observedAt: observedAt,
            sessions: []
        )
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }
}

private struct DelayedExpiringWaitAdapter: AgentProviderAdapter {
    let source: ObservationSourceDescriptor
    let isEnabled = true

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        try await Task.sleep(for: .milliseconds(50))
        let key = SessionKey(
            provider: source.provider,
            runtime: source.runtime,
            value: "expired-during-poll"
        )
        return EvidenceBatch.legacySnapshot(
            source: source,
            sequence: 1,
            observedAt: observedAt,
            sessions: [
                ObservedSessionSnapshot(
                    session: ObservedSession(key: key, lastActivity: observedAt),
                    claim: .handoffOpened(
                        token: HandoffToken(rawValue: "expired-handoff"),
                        reason: .input,
                        at: observedAt
                    ),
                    expiresAt: observedAt.addingTimeInterval(0.01)
                )
            ]
        )
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }
}

private actor FailingAfterFirstAdapter: AgentProviderAdapter {
    nonisolated let source = descriptor(
        source: SourceID(rawValue: "mock.failing"),
        provider: .mock,
        runtime: .mockFixture
    )
    nonisolated let isEnabled = true
    private var calls = 0

    func observations(observedAt: Date) async throws -> EvidenceBatch {
        calls += 1
        if calls > 1 { throw TestError.failed }
        return fixtureBatch(
            source: source,
            sequence: 1,
            observedAt: observedAt,
            fixtures: [Fixture(id: "waiting", state: .waiting(.permission))]
        )
    }

    func focus(_ session: AgentSession) async throws {
        throw AdapterError.focusUnavailable
    }

    enum TestError: Error { case failed }
}

private func descriptor(
    source: SourceID,
    provider: ProviderID,
    runtime: RuntimeSurfaceID
) -> ObservationSourceDescriptor {
    ObservationSourceDescriptor(
        id: source,
        provider: provider,
        runtime: runtime,
        contract: .localSnapshotV1,
        tier: .zeroTouch,
        capabilities: [
            .sessionDiscovery,
            .workState,
            .explicitInputWait,
            .explicitPermissionWait,
            .explicitChoiceWait,
            .explicitReviewWait,
            .completion,
        ]
    )
}

private func fixtureBatch(
    source: ObservationSourceDescriptor,
    sequence: UInt64,
    observedAt: Date,
    fixtures: [Fixture]
) -> EvidenceBatch {
    let sessions = fixtures.map { fixture -> ObservedSessionSnapshot in
        let key = SessionKey(
            provider: source.provider,
            runtime: source.runtime,
            value: fixture.id
        )
        let claim: LegacySnapshotLifecycleClaim
        switch fixture.state {
        case .working:
            claim = .workBegan(at: observedAt)
        case let .waiting(reason):
            claim = .handoffOpened(
                token: HandoffToken(rawValue: "handoff:\(fixture.id)"),
                reason: reason,
                at: observedAt
            )
        case .idle:
            claim = .workEnded(at: observedAt)
        case .done:
            claim = .sessionEnded(at: observedAt)
        case .unknown:
            claim = .presenceOnly
        }
        return ObservedSessionSnapshot(
            session: ObservedSession(key: key, label: fixture.label, lastActivity: observedAt),
            claim: claim
        )
    }
    return EvidenceBatch.legacySnapshot(
        source: source,
        sequence: sequence,
        observedAt: observedAt,
        sessions: sessions
    )
}
