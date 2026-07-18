import XCTest
@testable import Perch

final class AttentionReducerTests: XCTestCase {
    func testSessionKeyDistinguishesRuntimeSurfaces() {
        let desktop = SessionKey(provider: .codex, runtime: .codexDesktop, value: "same-id")
        let cli = SessionKey(
            provider: .codex,
            runtime: RuntimeSurfaceID(rawValue: "codex.cli"),
            value: "same-id"
        )

        XCTAssertNotEqual(desktop, cli)
        XCTAssertEqual(Set([desktop, cli]).count, 2)
    }

    func testAuthoritativeHandoffProducesTypedObservedWaitingUntilExpiry() throws {
        let source = testDescriptor("source.waiting")
        let key = testSessionKey(source)
        let openedAt = Date(timeIntervalSince1970: 100)
        let expiry = Date(timeIntervalSince1970: 200)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 1,
                observedAt: Date(timeIntervalSince1970: 110),
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key, label: "Typed wait"),
                        claim: .handoffOpened(
                            token: HandoffToken(rawValue: "h1"),
                            reason: .input,
                            at: openedAt
                        ),
                        expiresAt: expiry
                    ),
                ]
            ),
            from: source
        )

        let waiting = try XCTUnwrap(reducer.sessions(at: Date(timeIntervalSince1970: 150)).first)
        XCTAssertEqual(waiting.state, .waiting)
        XCTAssertEqual(waiting.attentionReason, .input)
        XCTAssertEqual(waiting.waitingOn, "input required")
        XCTAssertEqual(waiting.waitingSince, openedAt)
        XCTAssertEqual(waiting.confidence, .observed)

        let expired = try XCTUnwrap(reducer.sessions(at: expiry).first)
        XCTAssertEqual(expired.state, .unknown)
        XCTAssertEqual(expired.confidence, .unknown)
        XCTAssertNil(expired.attentionReason)
        XCTAssertNil(expired.waitingSince)
    }

    func testSupportingHandoffCannotProduceWaiting() throws {
        let source = testDescriptor("source.supporting")
        let key = testSessionKey(source)
        let at = Date(timeIntervalSince1970: 10)
        let item = evidence(
            id: "supporting-open",
            session: key,
            source: source.id,
            at: at,
            authority: .supporting,
            kind: .handoffOpened(token: HandoffToken(rawValue: "h1"), reason: .permission)
        )
        var reducer = AttentionReducer()

        try reducer.ingest(
            EvidenceBatch(
                source: source.id,
                sequence: 1,
                mode: .snapshot,
                observedAt: at,
                sessions: [ObservedSession(key: key)],
                items: [item]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testSourceCannotExceedDeclaredCapabilities() {
        let source = ObservationSourceDescriptor(
            id: SourceID(rawValue: "source.presence-only"),
            provider: .mock,
            runtime: .mockFixture,
            contract: .localSnapshotV1,
            tier: .zeroTouch,
            capabilities: [.sessionDiscovery]
        )
        let key = testSessionKey(source)
        let at = Date(timeIntervalSince1970: 10)
        let item = evidence(
            id: "unsupported-open",
            session: key,
            source: source.id,
            at: at,
            kind: .handoffOpened(token: HandoffToken(rawValue: "h1"), reason: .input)
        )
        var reducer = AttentionReducer()

        XCTAssertThrowsError(
            try reducer.ingest(
                EvidenceBatch(
                    source: source.id,
                    sequence: 1,
                    mode: .snapshot,
                    observedAt: at,
                    sessions: [ObservedSession(key: key)],
                    items: [item]
                ),
                from: source
            )
        ) { error in
            XCTAssertEqual(error as? AttentionReducerError, .undeclaredCapability(item.id))
        }
        XCTAssertTrue(reducer.sessions(at: at).isEmpty)
    }

    func testNonFocusSourceCannotInjectNativeSurface() throws {
        let source = testDescriptor("source.no-focus")
        let key = testSessionKey(source)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 1,
                observedAt: at,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(
                            key: key,
                            nativeSurface: .url(URL(string: "mock://session/1")!)
                        ),
                        claim: .workBegan(at: at)
                    ),
                ]
            ),
            from: source
        )

        XCTAssertNil(reducer.sessions(at: at).first?.nativeSurface)
    }

    func testFutureDatedEvidenceIsRejected() {
        let source = testDescriptor("source.future")
        let key = testSessionKey(source)
        let observedAt = Date(timeIntervalSince1970: 10)
        let item = evidence(
            id: "future-open",
            session: key,
            source: source.id,
            at: Date(timeIntervalSince1970: 20),
            kind: .handoffOpened(token: HandoffToken(rawValue: "h1"), reason: .input)
        )
        var reducer = AttentionReducer()

        XCTAssertThrowsError(
            try reducer.ingest(
                EvidenceBatch(
                    source: source.id,
                    sequence: 1,
                    mode: .snapshot,
                    observedAt: observedAt,
                    sessions: [ObservedSession(key: key)],
                    items: [item]
                ),
                from: source
            )
        ) { error in
            XCTAssertEqual(error as? AttentionReducerError, .invalidTimestamp(item.id))
        }
        XCTAssertTrue(reducer.sessions(at: observedAt).isEmpty)

        var futureBatchReducer = AttentionReducer()
        XCTAssertThrowsError(
            try futureBatchReducer.ingest(
                EvidenceBatch(
                    source: source.id,
                    sequence: 1,
                    mode: .snapshot,
                    observedAt: Date(timeIntervalSince1970: 20),
                    sessions: [ObservedSession(key: key)],
                    items: [item]
                ),
                from: source,
                receivedAt: observedAt
            )
        ) { error in
            XCTAssertEqual(error as? AttentionReducerError, .batchFromFuture(source.id))
        }
    }

    func testMatchingCloseReturnsActiveSessionToWorking() throws {
        let source = testDescriptor("source.close")
        let key = testSessionKey(source)
        let beganAt = Date(timeIntervalSince1970: 10)
        let openedAt = Date(timeIntervalSince1970: 20)
        let closedAt = Date(timeIntervalSince1970: 30)
        let token = HandoffToken(rawValue: "h1")
        var reducer = AttentionReducer()

        try reducer.ingest(
            batch(
                source: source,
                sequence: 1,
                mode: .snapshot,
                key: key,
                at: openedAt,
                items: [
                    evidence(id: "work", session: key, source: source.id, at: beganAt, kind: .workBegan),
                    evidence(id: "open", session: key, source: source.id, at: openedAt, kind: .handoffOpened(token: token, reason: .review)),
                ]
            ),
            from: source
        )
        try reducer.ingest(
            batch(
                source: source,
                sequence: 2,
                mode: .delta,
                key: key,
                at: closedAt,
                items: [
                    evidence(id: "close", session: key, source: source.id, at: closedAt, kind: .handoffClosed(token: token)),
                ]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: closedAt).first)
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.confidence, .observed)
        XCTAssertNil(session.attentionReason)
        XCTAssertNil(session.waitingSince)
    }

    func testExpiredCloseCannotResurrectOlderOpen() throws {
        let source = testDescriptor("source.expired-close")
        let key = testSessionKey(source)
        let token = HandoffToken(rawValue: "h1")
        let openedAt = Date(timeIntervalSince1970: 10)
        let closedAt = Date(timeIntervalSince1970: 20)
        let closeExpiry = Date(timeIntervalSince1970: 25)
        var reducer = AttentionReducer()

        let open = evidence(
            id: "open",
            session: key,
            source: source.id,
            at: openedAt,
            kind: .handoffOpened(token: token, reason: .input)
        )
        let close = SessionEvidence(
            id: EvidenceID(rawValue: "close"),
            session: key,
            source: source.id,
            eventAt: closedAt,
            observedAt: closedAt,
            expiresAt: closeExpiry,
            authority: .authoritative,
            kind: .handoffClosed(token: token)
        )
        try reducer.ingest(
            batch(
                source: source,
                sequence: 1,
                mode: .snapshot,
                key: key,
                at: closedAt,
                items: [open, close]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: Date(timeIntervalSince1970: 30)).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertNotEqual(session.state, .waiting)
        XCTAssertNil(session.attentionReason)
    }

    func testUnrelatedCloseFailsClosed() throws {
        let source = testDescriptor("source.bad-close")
        let key = testSessionKey(source)
        let openedAt = Date(timeIntervalSince1970: 20)
        let closedAt = Date(timeIntervalSince1970: 30)
        var reducer = AttentionReducer()

        try reducer.ingest(
            batch(
                source: source,
                sequence: 1,
                mode: .snapshot,
                key: key,
                at: openedAt,
                items: [
                    evidence(id: "open", session: key, source: source.id, at: openedAt, kind: .handoffOpened(token: HandoffToken(rawValue: "h1"), reason: .input)),
                ]
            ),
            from: source
        )
        try reducer.ingest(
            batch(
                source: source,
                sequence: 2,
                mode: .delta,
                key: key,
                at: closedAt,
                items: [
                    evidence(id: "wrong-close", session: key, source: source.id, at: closedAt, kind: .handoffClosed(token: HandoffToken(rawValue: "h2"))),
                ]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: closedAt).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testMultipleActiveHandoffsFailClosed() throws {
        let source = testDescriptor("source.multiple")
        let key = testSessionKey(source)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        try reducer.ingest(
            batch(
                source: source,
                sequence: 1,
                mode: .snapshot,
                key: key,
                at: at,
                items: [
                    evidence(id: "open-1", session: key, source: source.id, at: at, kind: .handoffOpened(token: HandoffToken(rawValue: "h1"), reason: .input)),
                    evidence(id: "open-2", session: key, source: source.id, at: at, kind: .handoffOpened(token: HandoffToken(rawValue: "h2"), reason: .permission)),
                ]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testSnapshotReplacementClearsMissingOpenButEmptyDeltaDoesNot() throws {
        let source = testDescriptor("source.snapshot")
        let key = testSessionKey(source)
        let openedAt = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 1,
                observedAt: openedAt,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .handoffOpened(
                            token: HandoffToken(rawValue: "h1"),
                            reason: .choice,
                            at: openedAt
                        )
                    ),
                ]
            ),
            from: source
        )
        try reducer.ingest(
            EvidenceBatch(
                source: source.id,
                sequence: 2,
                mode: .delta,
                observedAt: Date(timeIntervalSince1970: 20),
                sessions: [],
                items: []
            ),
            from: source
        )
        XCTAssertEqual(reducer.sessions(at: Date(timeIntervalSince1970: 20)).first?.state, .waiting)

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 3,
                observedAt: Date(timeIntervalSince1970: 30),
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .workBegan(at: Date(timeIntervalSince1970: 30))
                    ),
                ]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: Date(timeIntervalSince1970: 30)).first)
        XCTAssertEqual(session.state, .working)
        XCTAssertNil(session.attentionReason)
    }

    func testSourceFailureRemovesOnlyItsUrgentContribution() throws {
        let first = testDescriptor("source.first")
        let second = testDescriptor("source.second")
        let key = testSessionKey(first)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        for (index, source) in [first, second].enumerated() {
            try reducer.ingest(
                streamSnapshot(
                    source: source,
                    sequence: 1,
                    observedAt: at,
                    sessions: [
                        ObservedSessionSnapshot(
                            session: ObservedSession(key: key),
                            claim: .handoffOpened(
                                token: HandoffToken(rawValue: "h\(index)"),
                                reason: .permission,
                                at: at
                            )
                        ),
                    ]
                ),
                from: source
            )
        }

        reducer.markSourceFailed(first.id)
        let stillWaiting = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(stillWaiting.state, .waiting)
        XCTAssertEqual(stillWaiting.attentionReason, .permission)

        reducer.markSourceFailed(second.id)
        let stale = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(stale.state, .unknown)
        XCTAssertEqual(stale.confidence, .stale)
        XCTAssertNil(stale.attentionReason)
    }

    func testRecoveryHeartbeatDoesNotRestoreFailedWait() throws {
        let source = testDescriptor("source.recovery")
        let key = testSessionKey(source)
        let openedAt = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 1,
                observedAt: openedAt,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .handoffOpened(
                            token: HandoffToken(rawValue: "h1"),
                            reason: .input,
                            at: openedAt
                        )
                    ),
                ]
            ),
            from: source
        )
        reducer.markSourceFailed(source.id)

        let recoveredAt = Date(timeIntervalSince1970: 20)
        try reducer.ingest(
            batch(
                source: source,
                sequence: 2,
                mode: .delta,
                key: key,
                at: recoveredAt,
                items: [
                    evidence(
                        id: "heartbeat",
                        session: key,
                        source: source.id,
                        at: recoveredAt,
                        authority: .presence,
                        kind: .heartbeat
                    ),
                ]
            ),
            from: source
        )

        let session = try XCTUnwrap(reducer.sessions(at: recoveredAt).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testConflictingAuthoritativeSourcesFailClosed() throws {
        let waitingSource = testDescriptor("source.conflict.waiting")
        let workingSource = testDescriptor("source.conflict.working")
        let key = testSessionKey(waitingSource)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: waitingSource,
                sequence: 1,
                observedAt: at,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .handoffOpened(
                            token: HandoffToken(rawValue: "h1"),
                            reason: .input,
                            at: at
                        )
                    ),
                ]
            ),
            from: waitingSource
        )
        try reducer.ingest(
            streamSnapshot(
                source: workingSource,
                sequence: 1,
                observedAt: at,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .workBegan(at: at)
                    ),
                ]
            ),
            from: workingSource
        )

        let session = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testUncorrelatedWaitsFromTwoSourcesFailClosed() throws {
        let first = testDescriptor("source.wait.first")
        let second = testDescriptor("source.wait.second")
        let key = testSessionKey(first)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        for (index, source) in [first, second].enumerated() {
            try reducer.ingest(
                streamSnapshot(
                    source: source,
                    sequence: 1,
                    observedAt: at,
                    sessions: [
                        ObservedSessionSnapshot(
                            session: ObservedSession(key: key),
                            claim: .handoffOpened(
                                token: HandoffToken(rawValue: "source-\(index)"),
                                reason: .input,
                                at: at
                            )
                        ),
                    ]
                ),
                from: source
            )
        }

        let session = try XCTUnwrap(reducer.sessions(at: at).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertNil(session.attentionReason)
    }

    func testSourceDescriptorCannotMutate() throws {
        let original = testDescriptor("source.descriptor")
        let changed = ObservationSourceDescriptor(
            id: original.id,
            provider: .codex,
            runtime: .codexDesktop,
            contract: .eventStreamV1,
            tier: .zeroTouch,
            capabilities: original.capabilities
        )
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()
        try reducer.ingest(
            streamSnapshot(
                source: original,
                sequence: 1,
                observedAt: at,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: testSessionKey(original)),
                        claim: .workBegan(at: at)
                    ),
                ]
            ),
            from: original
        )

        let changedKey = SessionKey(
            provider: changed.provider,
            runtime: changed.runtime,
            value: "session-1"
        )
        XCTAssertThrowsError(
            try reducer.ingest(
                streamSnapshot(
                    source: changed,
                    sequence: 2,
                    observedAt: at,
                    sessions: [
                        ObservedSessionSnapshot(
                            session: ObservedSession(key: changedKey),
                            claim: .workBegan(at: at)
                        ),
                    ]
                ),
                from: changed
            )
        ) { error in
            XCTAssertEqual(error as? AttentionReducerError, .descriptorChanged(original.id))
        }
        XCTAssertEqual(reducer.sessions(at: at).first?.state, .unknown)
        XCTAssertEqual(reducer.sessions(at: at).first?.confidence, .stale)
    }

    func testLocalSnapshotContractRejectsDelta() throws {
        let source = ObservationSourceDescriptor(
            id: SourceID(rawValue: "source.local"),
            provider: .mock,
            runtime: .mockFixture,
            contract: .localSnapshotV1,
            tier: .zeroTouch,
            capabilities: [.sessionDiscovery]
        )
        let key = testSessionKey(source)
        let at = Date(timeIntervalSince1970: 10)
        var reducer = AttentionReducer()

        XCTAssertThrowsError(
            try reducer.ingest(
                EvidenceBatch(
                    source: source.id,
                    sequence: 1,
                    mode: .delta,
                    observedAt: at,
                    sessions: [ObservedSession(key: key)],
                    items: []
                ),
                from: source
            )
        ) { error in
            XCTAssertEqual(error as? AttentionReducerError, .contractModeMismatch(.localSnapshotV1))
        }
        XCTAssertTrue(reducer.sessions(at: at).isEmpty)
    }

    func testOlderBatchCannotReopenClosedHandoff() throws {
        let source = testDescriptor("source.sequence")
        let key = testSessionKey(source)
        let token = HandoffToken(rawValue: "h1")
        let openedAt = Date(timeIntervalSince1970: 10)
        let closedAt = Date(timeIntervalSince1970: 20)
        var reducer = AttentionReducer()

        let openBatch = batch(
            source: source,
            sequence: 1,
            mode: .snapshot,
            key: key,
            at: openedAt,
            items: [
                evidence(id: "open", session: key, source: source.id, at: openedAt, kind: .handoffOpened(token: token, reason: .input)),
            ]
        )
        try reducer.ingest(openBatch, from: source)
        try reducer.ingest(
            batch(
                source: source,
                sequence: 2,
                mode: .delta,
                key: key,
                at: closedAt,
                items: [
                    evidence(id: "close", session: key, source: source.id, at: closedAt, kind: .handoffClosed(token: token)),
                ]
            ),
            from: source
        )

        XCTAssertEqual(try reducer.ingest(openBatch, from: source), .ignoredOutOfOrder)
        let session = try XCTUnwrap(reducer.sessions(at: closedAt).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .stale)
        XCTAssertNil(session.attentionReason)
    }

    func testNewerSnapshotCannotRegressLifecycleWatermark() throws {
        let source = testDescriptor("source.snapshot-watermark")
        let key = testSessionKey(source)
        let workingAt = Date(timeIntervalSince1970: 20)
        let observedAt = Date(timeIntervalSince1970: 30)
        var reducer = AttentionReducer()

        try reducer.ingest(
            streamSnapshot(
                source: source,
                sequence: 1,
                observedAt: workingAt,
                sessions: [
                    ObservedSessionSnapshot(
                        session: ObservedSession(key: key),
                        claim: .workBegan(at: workingAt)
                    ),
                ]
            ),
            from: source
        )

        XCTAssertThrowsError(
            try reducer.ingest(
                streamSnapshot(
                    source: source,
                    sequence: 2,
                    observedAt: observedAt,
                    sessions: [
                        ObservedSessionSnapshot(
                            session: ObservedSession(key: key),
                            claim: .handoffOpened(
                                token: HandoffToken(rawValue: "older"),
                                reason: .input,
                                at: Date(timeIntervalSince1970: 10)
                            )
                        ),
                    ]
                ),
                from: source
            )
        ) { error in
            XCTAssertEqual(
                error as? AttentionReducerError,
                .eventTimestampRegressed(EvidenceID(rawValue: "session-1:handoff:older"))
            )
        }
        let session = try XCTUnwrap(reducer.sessions(at: observedAt).first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertEqual(session.confidence, .stale)
        XCTAssertNil(session.attentionReason)
    }
}

private func testDescriptor(_ sourceID: String) -> ObservationSourceDescriptor {
    ObservationSourceDescriptor(
        id: SourceID(rawValue: sourceID),
        provider: .mock,
        runtime: .mockFixture,
        contract: .eventStreamV1,
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

private func testSessionKey(_ source: ObservationSourceDescriptor) -> SessionKey {
    SessionKey(provider: source.provider, runtime: source.runtime, value: "session-1")
}

private func evidence(
    id: String,
    session: SessionKey,
    source: SourceID,
    at: Date,
    authority: EvidenceAuthority = .authoritative,
    kind: EvidenceKind
) -> SessionEvidence {
    SessionEvidence(
        id: EvidenceID(rawValue: id),
        session: session,
        source: source,
        eventAt: at,
        observedAt: at,
        authority: authority,
        kind: kind
    )
}

private func batch(
    source: ObservationSourceDescriptor,
    sequence: UInt64,
    mode: EvidenceBatch.Mode,
    key: SessionKey,
    at: Date,
    items: [SessionEvidence]
) -> EvidenceBatch {
    EvidenceBatch(
        source: source.id,
        sequence: sequence,
        mode: mode,
        observedAt: at,
        sessions: [ObservedSession(key: key)],
        items: items
    )
}

private func streamSnapshot(
    source: ObservationSourceDescriptor,
    sequence: UInt64,
    observedAt: Date,
    sessions: [ObservedSessionSnapshot]
) -> EvidenceBatch {
    precondition(source.contract == .eventStreamV1)
    let items = sessions.compactMap { snapshot -> SessionEvidence? in
        let event: (String, Date, EvidenceKind)?
        switch snapshot.claim {
        case .presenceOnly:
            event = nil
        case let .workBegan(at):
            event = ("working", at, .workBegan)
        case let .handoffOpened(token, reason, at):
            event = ("handoff:\(token.rawValue)", at, .handoffOpened(token: token, reason: reason))
        case let .workEnded(at):
            event = ("idle", at, .workEnded)
        case let .sessionEnded(at):
            event = ("done", at, .sessionEnded)
        }
        guard let event else { return nil }
        return SessionEvidence(
            id: EvidenceID(rawValue: "\(snapshot.session.key.value):\(event.0)"),
            session: snapshot.session.key,
            source: source.id,
            eventAt: event.1,
            observedAt: observedAt,
            expiresAt: snapshot.expiresAt,
            authority: .authoritative,
            kind: event.2
        )
    }
    return EvidenceBatch(
        source: source.id,
        sequence: sequence,
        mode: .snapshot,
        observedAt: observedAt,
        sessions: sessions.map(\.session),
        items: items
    )
}
