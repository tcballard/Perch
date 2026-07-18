import XCTest
@testable import Perch

final class AttentionPresentationTests: XCTestCase {
    func testAttentionContainsOnlyWaitingSessions() {
        let presentation = AttentionPresentation(sessions: [
            session(id: "work", state: .working),
            session(id: "wait", state: .waiting, attentionReason: .permission),
            session(id: "idle", state: .idle),
        ])

        XCTAssertEqual(presentation.observedCount, 3)
        XCTAssertEqual(presentation.waitingCount, 1)
        XCTAssertEqual(presentation.waitingSessions.map(\.id.value), ["wait"])
        XCTAssertEqual(presentation.allSessions.count, 3)
    }

    func testZeroOneAndThreeWaitFixturesPreserveExactCount() {
        for count in [0, 1, 3] {
            let sessions = (0..<count).map { session(id: "wait-\($0)", state: .waiting, attentionReason: .input) }
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

    func testWaitingActionsUseTypedCategories() {
        let values: [(AttentionReason, WaitingAction)] = [
            (.input, .input),
            (.permission, .permission),
            (.choice, .choice),
            (.review, .review),
        ]

        for (reason, expected) in values {
            XCTAssertEqual(WaitingAction(reason: reason), expected)
        }
    }

    func testProjectIdentityLeadsAndIsBounded() {
        let longName = String(repeating: "A", count: 40)
        let item = SessionPresentation(session: session(id: "long", state: .waiting, attentionReason: .input, label: longName))

        XCTAssertEqual(item.projectName.count, 30)
        XCTAssertEqual(item.providerName, "Codex")
    }

    func testFocusAvailabilityReflectsNativeSurface() {
        let available = SessionPresentation(session: session(
            id: "focus",
            state: .waiting,
            attentionReason: .input,
            nativeSurface: .url(URL(string: "codex://threads/example")!)
        ))
        let unavailable = SessionPresentation(session: session(id: "none", state: .waiting, attentionReason: .input))

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
            session(id: "waiting", state: .waiting, attentionReason: .input),
        ]).dominantState, .waiting)
    }

    private func session(
        id: String,
        state: AgentState,
        confidence: StateConfidence = .observed,
        attentionReason: AttentionReason? = nil,
        label: String? = nil,
        nativeSurface: NativeSurfaceHandle? = nil
    ) -> AgentSession {
        AgentSession(
            provider: .codex,
            runtime: .codexDesktop,
            id: id,
            label: label,
            nativeSurface: nativeSurface,
            state: state,
            attentionReason: attentionReason,
            confidence: confidence
        )
    }
}
