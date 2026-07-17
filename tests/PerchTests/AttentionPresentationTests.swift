import XCTest
@testable import Perch

final class AttentionPresentationTests: XCTestCase {
    func testAttentionContainsOnlyWaitingSessions() {
        let presentation = AttentionPresentation(sessions: [
            session(id: "work", state: .working),
            session(id: "wait", state: .waiting, waitingOn: "permission required"),
            session(id: "idle", state: .idle),
        ])

        XCTAssertEqual(presentation.observedCount, 3)
        XCTAssertEqual(presentation.waitingCount, 1)
        XCTAssertEqual(presentation.waitingSessions.map(\.id.value), ["wait"])
        XCTAssertEqual(presentation.allSessions.count, 3)
    }

    func testZeroOneAndThreeWaitFixturesPreserveExactCount() {
        for count in [0, 1, 3] {
            let sessions = (0..<count).map { session(id: "wait-\($0)", state: .waiting) }
            let presentation = AttentionPresentation(sessions: sessions)

            XCTAssertEqual(presentation.waitingCount, count)
            XCTAssertEqual(presentation.waitingSessions.count, count)
        }
    }

    func testUnknownAndStaleSessionsAreUncertainNotWaiting() {
        let presentation = AttentionPresentation(sessions: [
            session(id: "unknown", state: .unknown, confidence: .unknown),
            session(id: "stale", state: .unknown, confidence: .stale),
            session(id: "unverified-wait", state: .waiting, confidence: .unknown),
            session(id: "stale-work", state: .working, confidence: .stale),
        ])

        XCTAssertEqual(presentation.waitingCount, 0)
        XCTAssertEqual(presentation.workingCount, 0)
        XCTAssertEqual(presentation.restingCount, 0)
        XCTAssertEqual(presentation.uncertainCount, 4)
        XCTAssertEqual(presentation.dominantState, .unknown)
        XCTAssertNil(presentation.allSessions.first { $0.id.value == "unverified-wait" }?.waitingAction)
        XCTAssertEqual(
            presentation.waitingCount + presentation.workingCount + presentation.restingCount + presentation.uncertainCount,
            presentation.observedCount
        )
    }

    func testWaitingActionsUseBoundedCategories() {
        let values: [(String?, WaitingAction)] = [
            ("permission required", .permission),
            ("approval required", .permission),
            ("choice required", .choice),
            ("review required", .review),
            ("provider-specific untrusted text", .input),
        ]

        for (waitingOn, expected) in values {
            XCTAssertEqual(WaitingAction(waitingOn: waitingOn), expected)
        }
    }

    func testProjectIdentityLeadsAndIsBounded() {
        let longName = String(repeating: "A", count: 40)
        let item = SessionPresentation(session: session(id: "long", state: .waiting, label: longName))

        XCTAssertEqual(item.projectName.count, 30)
        XCTAssertEqual(item.providerName, "Codex")
    }

    func testFocusAvailabilityReflectsNativeSurface() {
        let available = SessionPresentation(session: session(
            id: "focus",
            state: .waiting,
            nativeSurface: .url(URL(string: "codex://threads/example")!)
        ))
        let unavailable = SessionPresentation(session: session(id: "none", state: .waiting))

        XCTAssertTrue(available.canFocus)
        XCTAssertFalse(unavailable.canFocus)
    }

    func testOverviewAggregatesAtEightObservedAgents() {
        let seven = AttentionPresentation(sessions: (0..<7).map { session(id: "\($0)", state: .working) })
        let eight = AttentionPresentation(sessions: (0..<8).map { session(id: "\($0)", state: .working) })
        let twenty = AttentionPresentation(sessions: (0..<20).map { session(id: "\($0)", state: .idle) })

        XCTAssertFalse(seven.usesAggregatedOverview)
        XCTAssertTrue(eight.usesAggregatedOverview)
        XCTAssertTrue(twenty.usesAggregatedOverview)
        XCTAssertEqual(twenty.restingCount, 20)
    }

    func testDominantStateUsesConservativeAttentionPriority() {
        XCTAssertEqual(AttentionPresentation(sessions: []).dominantState, .unknown)
        XCTAssertEqual(AttentionPresentation(sessions: [session(id: "unknown", state: .unknown)]).dominantState, .unknown)
        XCTAssertEqual(AttentionPresentation(sessions: [session(id: "idle", state: .idle)]).dominantState, .idle)
        XCTAssertEqual(AttentionPresentation(sessions: [
            session(id: "idle", state: .idle),
            session(id: "working", state: .working),
        ]).dominantState, .working)
        XCTAssertEqual(AttentionPresentation(sessions: [
            session(id: "working", state: .working),
            session(id: "waiting", state: .waiting),
        ]).dominantState, .waiting)
    }

    private func session(
        id: String,
        state: AgentState,
        confidence: StateConfidence = .observed,
        waitingOn: String? = nil,
        label: String? = nil,
        nativeSurface: NativeSurfaceHandle? = nil
    ) -> AgentSession {
        AgentSession(
            provider: .codex,
            id: id,
            label: label,
            nativeSurface: nativeSurface,
            state: state,
            waitingOn: waitingOn,
            confidence: confidence
        )
    }
}
