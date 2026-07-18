import Foundation

enum AttentionReducerError: Error, Equatable {
    case unsupportedBatchSchema(UInt)
    case unsupportedEvidenceSchema(UInt)
    case sourceMismatch
    case sessionIdentityMismatch(SessionKey)
    case duplicateSessionKey(SessionKey)
    case duplicateEvidenceID(EvidenceID)
    case missingSessionMetadata(SessionKey)
    case sequenceConflict(SourceID, UInt64)
    case undeclaredCapability(EvidenceID)
    case invalidTimestamp(EvidenceID)
    case descriptorChanged(SourceID)
    case unsupportedContract(ObservationContractID)
    case contractModeMismatch(ObservationContractID)
    case capacityExceeded(SourceID)
    case batchTimestampRegressed(SourceID)
    case eventTimestampRegressed(EvidenceID)
    case batchFromFuture(SourceID)
}

enum EvidenceIngestResult: Equatable {
    case accepted
    case duplicate
    case ignoredOutOfOrder
}

struct AttentionReducer {
    private static let maximumSessionsPerSource = 256
    private static let maximumEvidencePerSource = 4_096
    private static let maximumEvidencePerSession = 256

    private struct SourceState {
        let descriptor: ObservationSourceDescriptor
        var sequence: UInt64
        var lastBatch: EvidenceBatch
        var sessions: [SessionKey: ObservedSession]
        var evidence: [EvidenceID: SessionEvidence]
        var lifecycleWatermarks: [SessionKey: Date]
        var isFailed: Bool
    }

    private struct SourceAssessment {
        let state: AgentState?
        let reason: AttentionReason?
        let token: HandoffToken?
        let waitingSince: Date?
        let isInvalid: Bool
    }

    private struct ActiveHandoff {
        let reason: AttentionReason
        let openedAt: Date
        let expiresAt: Date?
    }

    private var sources: [SourceID: SourceState] = [:]

    @discardableResult
    mutating func ingest(
        _ batch: EvidenceBatch,
        from descriptor: ObservationSourceDescriptor,
        receivedAt: Date? = nil
    ) throws -> EvidenceIngestResult {
        do {
            try validate(batch, from: descriptor, receivedAt: receivedAt)
        } catch {
            markSourceFailed(descriptor.id)
            throw error
        }

        if var current = sources[descriptor.id] {
            guard current.descriptor == descriptor else {
                current.isFailed = true
                current.evidence.removeAll()
                sources[descriptor.id] = current
                throw AttentionReducerError.descriptorChanged(descriptor.id)
            }
            if batch.sequence < current.sequence {
                current.isFailed = true
                current.evidence.removeAll()
                sources[descriptor.id] = current
                return .ignoredOutOfOrder
            }
            guard batch.observedAt >= current.lastBatch.observedAt else {
                current.isFailed = true
                current.evidence.removeAll()
                sources[descriptor.id] = current
                throw AttentionReducerError.batchTimestampRegressed(descriptor.id)
            }
            if batch.sequence == current.sequence {
                if batch == current.lastBatch { return .duplicate }
                current.isFailed = true
                current.evidence.removeAll()
                sources[descriptor.id] = current
                throw AttentionReducerError.sequenceConflict(descriptor.id, batch.sequence)
            }
        }

        var lifecycleWatermarks = sources[descriptor.id]?.lifecycleWatermarks ?? [:]
        let lifecycleItems = batch.items.filter { item in
            item.authority == .authoritative && Self.isLifecycle(item.kind)
        }
        let incomingBySession = Dictionary(grouping: lifecycleItems) { $0.session }
        for (session, items) in incomingBySession {
            guard let newest = items.max(by: { $0.eventAt < $1.eventAt }) else { continue }
            if let watermark = lifecycleWatermarks[session], newest.eventAt < watermark {
                markSourceFailed(descriptor.id)
                throw AttentionReducerError.eventTimestampRegressed(newest.id)
            }
            lifecycleWatermarks[session] = max(
                lifecycleWatermarks[session] ?? .distantPast,
                newest.eventAt
            )
        }

        var sessionIndex: [SessionKey: ObservedSession]
        var evidenceIndex: [EvidenceID: SessionEvidence]
        switch batch.mode {
        case .snapshot:
            sessionIndex = try Self.indexSessions(batch.sessions)
            evidenceIndex = try Self.indexEvidence(batch.items)
        case .delta:
            sessionIndex = sources[descriptor.id]?.sessions ?? [:]
            for session in batch.sessions {
                sessionIndex[session.key] = session
            }
            evidenceIndex = sources[descriptor.id]?.evidence ?? [:]
            for item in batch.items {
                if let current = evidenceIndex[item.id], current != item {
                    var failed = sources[descriptor.id]
                    failed?.isFailed = true
                    failed?.evidence.removeAll()
                    if let failed { sources[descriptor.id] = failed }
                    throw AttentionReducerError.duplicateEvidenceID(item.id)
                }
                evidenceIndex[item.id] = item
            }
        }

        for item in evidenceIndex.values where sessionIndex[item.session] == nil {
            markSourceFailed(descriptor.id)
            throw AttentionReducerError.missingSessionMetadata(item.session)
        }
        let evidenceBySession = Dictionary(grouping: evidenceIndex.values) { $0.session }
        guard sessionIndex.count <= Self.maximumSessionsPerSource,
              evidenceIndex.count <= Self.maximumEvidencePerSource,
              lifecycleWatermarks.count <= Self.maximumEvidencePerSource,
              evidenceBySession.values.allSatisfy({ $0.count <= Self.maximumEvidencePerSession }) else {
            markSourceFailed(descriptor.id)
            throw AttentionReducerError.capacityExceeded(descriptor.id)
        }

        sources[descriptor.id] = SourceState(
            descriptor: descriptor,
            sequence: batch.sequence,
            lastBatch: batch,
            sessions: sessionIndex,
            evidence: evidenceIndex,
            lifecycleWatermarks: lifecycleWatermarks,
            isFailed: false
        )
        return .accepted
    }

    mutating func markSourceFailed(_ source: SourceID) {
        guard var current = sources[source] else { return }
        current.isFailed = true
        current.evidence.removeAll()
        sources[source] = current
    }

    mutating func removeSource(_ source: SourceID) {
        sources.removeValue(forKey: source)
    }

    func sessions(at now: Date) -> [AgentSession] {
        let keys = Set(sources.values.flatMap { $0.sessions.keys })
        return keys.compactMap { key in
            project(key, at: now)
        }
    }

    private func project(_ key: SessionKey, at now: Date) -> AgentSession? {
        let contributions = sources.values.compactMap { source -> (SourceState, ObservedSession)? in
            guard let session = source.sessions[key] else { return nil }
            return (source, session)
        }
        guard !contributions.isEmpty else { return nil }

        let orderedMetadata = contributions.sorted { lhs, rhs in
            let leftActivity = lhs.1.lastActivity ?? .distantPast
            let rightActivity = rhs.1.lastActivity ?? .distantPast
            if leftActivity != rightActivity { return leftActivity > rightActivity }
            if lhs.0.lastBatch.observedAt != rhs.0.lastBatch.observedAt {
                return lhs.0.lastBatch.observedAt > rhs.0.lastBatch.observedAt
            }
            return lhs.0.descriptor.id.rawValue < rhs.0.descriptor.id.rawValue
        }
        let label = orderedMetadata.lazy.compactMap { $0.1.label }.first
        let workingDirectory = orderedMetadata.lazy.compactMap { $0.1.workingDirectory }.first
        let nativeSurface = orderedMetadata.lazy.compactMap { contribution -> NativeSurfaceHandle? in
            guard !contribution.0.isFailed,
                  contribution.0.descriptor.capabilities.contains(.focus) else { return nil }
            return contribution.1.nativeSurface
        }.first
        let validatedVersion = orderedMetadata.lazy.compactMap { $0.1.validatedProviderVersion }.first
        let lastActivity = orderedMetadata.compactMap { $0.1.lastActivity }.max()

        let healthy = contributions.filter { !$0.0.isFailed }
        let assessments = healthy.map { contribution in
            let source = contribution.0
            Self.assess(
                source.evidence.values.filter { $0.session == key },
                at: now
            )
        }
        if assessments.contains(where: \.isInvalid) {
            return AgentSession(
                provider: key.provider,
                runtime: key.runtime,
                id: key.value,
                label: label,
                workingDirectory: workingDirectory,
                nativeSurface: nativeSurface,
                state: .unknown,
                lastActivity: lastActivity,
                confidence: .unknown,
                validatedProviderVersion: validatedVersion
            )
        }

        let authoritative = assessments.filter { $0.state != nil }
        guard let first = authoritative.first, let firstState = first.state else {
            let confidence: StateConfidence = healthy.isEmpty ? .stale : .unknown
            return AgentSession(
                provider: key.provider,
                runtime: key.runtime,
                id: key.value,
                label: label,
                workingDirectory: workingDirectory,
                nativeSurface: nativeSurface,
                state: .unknown,
                lastActivity: lastActivity,
                confidence: confidence,
                validatedProviderVersion: validatedVersion
            )
        }

        guard authoritative.allSatisfy({ $0.state == firstState }) else {
            return AgentSession(
                provider: key.provider,
                runtime: key.runtime,
                id: key.value,
                label: label,
                workingDirectory: workingDirectory,
                nativeSurface: nativeSurface,
                state: .unknown,
                lastActivity: lastActivity,
                confidence: .unknown,
                validatedProviderVersion: validatedVersion
            )
        }

        if firstState == .waiting {
            guard authoritative.count == 1,
                  let reason = first.reason,
                  first.token != nil,
                  let waitingSince = first.waitingSince else {
                return AgentSession(
                    provider: key.provider,
                    runtime: key.runtime,
                    id: key.value,
                    label: label,
                    workingDirectory: workingDirectory,
                    nativeSurface: nativeSurface,
                    state: .unknown,
                    lastActivity: lastActivity,
                    confidence: .unknown,
                    validatedProviderVersion: validatedVersion
                )
            }
            return AgentSession(
                provider: key.provider,
                runtime: key.runtime,
                id: key.value,
                label: label,
                workingDirectory: workingDirectory,
                nativeSurface: nativeSurface,
                state: .waiting,
                attentionReason: reason,
                lastActivity: lastActivity,
                confidence: .observed,
                validatedProviderVersion: validatedVersion,
                waitingSince: waitingSince
            )
        }

        return AgentSession(
            provider: key.provider,
            runtime: key.runtime,
            id: key.value,
            label: label,
            workingDirectory: workingDirectory,
            nativeSurface: nativeSurface,
            state: firstState,
            lastActivity: lastActivity,
            confidence: .observed,
            validatedProviderVersion: validatedVersion
        )
    }

    private func validate(
        _ batch: EvidenceBatch,
        from descriptor: ObservationSourceDescriptor,
        receivedAt: Date?
    ) throws {
        guard batch.schemaVersion == EvidenceBatch.currentSchemaVersion else {
            throw AttentionReducerError.unsupportedBatchSchema(batch.schemaVersion)
        }
        guard batch.source == descriptor.id else {
            throw AttentionReducerError.sourceMismatch
        }
        if let receivedAt, batch.observedAt > receivedAt {
            throw AttentionReducerError.batchFromFuture(descriptor.id)
        }
        guard descriptor.contract == .localSnapshotV1 || descriptor.contract == .eventStreamV1 else {
            throw AttentionReducerError.unsupportedContract(descriptor.contract)
        }
        if descriptor.contract == .localSnapshotV1, batch.mode != .snapshot {
            throw AttentionReducerError.contractModeMismatch(descriptor.contract)
        }
        guard batch.sessions.count <= Self.maximumSessionsPerSource,
              batch.items.count <= Self.maximumEvidencePerSource else {
            throw AttentionReducerError.capacityExceeded(descriptor.id)
        }
        _ = try Self.indexSessions(batch.sessions)
        _ = try Self.indexEvidence(batch.items)

        for session in batch.sessions where
            session.key.provider != descriptor.provider || session.key.runtime != descriptor.runtime {
            throw AttentionReducerError.sessionIdentityMismatch(session.key)
        }
        for item in batch.items {
            guard item.schemaVersion == SessionEvidence.currentSchemaVersion else {
                throw AttentionReducerError.unsupportedEvidenceSchema(item.schemaVersion)
            }
            guard item.source == descriptor.id else {
                throw AttentionReducerError.sourceMismatch
            }
            guard item.session.provider == descriptor.provider,
                  item.session.runtime == descriptor.runtime else {
                throw AttentionReducerError.sessionIdentityMismatch(item.session)
            }
            guard item.eventAt <= item.observedAt,
                  item.observedAt <= batch.observedAt,
                  item.expiresAt == nil || item.expiresAt! >= item.eventAt else {
                throw AttentionReducerError.invalidTimestamp(item.id)
            }
            guard Self.supports(item.kind, capabilities: descriptor.capabilities) else {
                throw AttentionReducerError.undeclaredCapability(item.id)
            }
        }
    }

    private static func indexSessions(
        _ sessions: [ObservedSession]
    ) throws -> [SessionKey: ObservedSession] {
        var result: [SessionKey: ObservedSession] = [:]
        for session in sessions {
            guard result[session.key] == nil else {
                throw AttentionReducerError.duplicateSessionKey(session.key)
            }
            result[session.key] = session
        }
        return result
    }

    private static func indexEvidence(
        _ evidence: [SessionEvidence]
    ) throws -> [EvidenceID: SessionEvidence] {
        var result: [EvidenceID: SessionEvidence] = [:]
        for item in evidence {
            if let current = result[item.id] {
                guard current == item else {
                    throw AttentionReducerError.duplicateEvidenceID(item.id)
                }
                continue
            }
            result[item.id] = item
        }
        return result
    }

    private static func assess<S: Sequence>(
        _ evidence: S,
        at now: Date
    ) -> SourceAssessment where S.Element == SessionEvidence {
        let events = evidence
            .filter { item in
                item.authority == .authoritative
            }
            .sorted { lhs, rhs in
                if lhs.eventAt != rhs.eventAt { return lhs.eventAt < rhs.eventAt }
                if lhs.observedAt != rhs.observedAt { return lhs.observedAt < rhs.observedAt }
                let leftPriority = eventPriority(lhs.kind)
                let rightPriority = eventPriority(rhs.kind)
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        var state: AgentState?
        var stateEvidence: SessionEvidence?
        var active: [HandoffToken: ActiveHandoff] = [:]
        var seenTokens = Set<HandoffToken>()
        var invalid = false

        for event in events {
            switch event.kind {
            case .sessionSeen, .heartbeat:
                break
            case .workBegan:
                state = .working
                active.removeAll()
                seenTokens.removeAll()
                invalid = false
                stateEvidence = event
            case let .handoffOpened(token, reason):
                if seenTokens.contains(token) || !active.isEmpty {
                    invalid = true
                }
                seenTokens.insert(token)
                active[token] = ActiveHandoff(
                    reason: reason,
                    openedAt: event.eventAt,
                    expiresAt: event.expiresAt
                )
                state = .waiting
                stateEvidence = event
            case let .handoffClosed(token):
                guard active.removeValue(forKey: token) != nil else {
                    invalid = true
                    continue
                }
                state = active.isEmpty ? .working : .waiting
                if active.isEmpty { invalid = false }
                stateEvidence = event
            case .workEnded:
                active.removeAll()
                seenTokens.removeAll()
                invalid = false
                state = .idle
                stateEvidence = event
            case .sessionEnded:
                active.removeAll()
                seenTokens.removeAll()
                invalid = false
                state = .done
                stateEvidence = event
            }
        }

        if invalid {
            return SourceAssessment(
                state: nil,
                reason: nil,
                token: nil,
                waitingSince: nil,
                isInvalid: true
            )
        }
        let currentHandoffs = active.values.filter { handoff in
            handoff.expiresAt == nil || handoff.expiresAt! > now
        }
        guard !currentHandoffs.isEmpty else {
            guard active.isEmpty,
                  let stateEvidence,
                  stateEvidence.expiresAt == nil || stateEvidence.expiresAt! > now else {
                return SourceAssessment(
                    state: nil,
                    reason: nil,
                    token: nil,
                    waitingSince: nil,
                    isInvalid: false
                )
            }
            return SourceAssessment(
                state: state,
                reason: nil,
                token: nil,
                waitingSince: nil,
                isInvalid: false
            )
        }

        guard currentHandoffs.count == 1,
              let entry = active.first(where: { entry in
                  entry.value.expiresAt == nil || entry.value.expiresAt! > now
              }) else {
            return SourceAssessment(
                state: nil,
                reason: nil,
                token: nil,
                waitingSince: nil,
                isInvalid: true
            )
        }
        return SourceAssessment(
            state: .waiting,
            reason: entry.value.reason,
            token: entry.key,
            waitingSince: entry.value.openedAt,
            isInvalid: false
        )
    }

    private static func supports(
        _ kind: EvidenceKind,
        capabilities: Set<ObservationCapability>
    ) -> Bool {
        switch kind {
        case .sessionSeen, .heartbeat:
            return capabilities.contains(.sessionDiscovery)
        case .workBegan, .workEnded:
            return capabilities.contains(.workState)
        case let .handoffOpened(_, reason):
            switch reason {
            case .input: return capabilities.contains(.explicitInputWait)
            case .permission: return capabilities.contains(.explicitPermissionWait)
            case .choice: return capabilities.contains(.explicitChoiceWait)
            case .review: return capabilities.contains(.explicitReviewWait)
            }
        case .handoffClosed:
            return capabilities.contains(.explicitInputWait) ||
                capabilities.contains(.explicitPermissionWait) ||
                capabilities.contains(.explicitChoiceWait) ||
                capabilities.contains(.explicitReviewWait)
        case .sessionEnded:
            return capabilities.contains(.completion)
        }
    }

    private static func isLifecycle(_ kind: EvidenceKind) -> Bool {
        switch kind {
        case .sessionSeen, .heartbeat: return false
        case .workBegan, .handoffOpened, .handoffClosed, .workEnded, .sessionEnded:
            return true
        }
    }

    private static func eventPriority(_ kind: EvidenceKind) -> Int {
        switch kind {
        case .sessionSeen: 0
        case .heartbeat: 1
        case .workBegan: 2
        case .handoffOpened: 3
        case .handoffClosed: 4
        case .workEnded: 5
        case .sessionEnded: 6
        }
    }

}
