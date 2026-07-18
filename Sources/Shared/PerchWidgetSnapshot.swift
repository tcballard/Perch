import Foundation

struct PerchWidgetSnapshot: Codable, Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case waiting
        case working
        case resting
        case uncertain
    }

    struct WaitingHandoff: Codable, Equatable, Sendable {
        let projectName: String
        let action: String
        let waitingSince: Date
        let providerName: String
        let focusURL: URL?
    }

    struct Content: Equatable, Sendable {
        let dominantState: State
        let waitingCount: Int
        let workingCount: Int
        let restingCount: Int
        let uncertainCount: Int
        let waitingHandoffs: [WaitingHandoff]
    }

    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let dominantState: State
    let waitingCount: Int
    let workingCount: Int
    let restingCount: Int
    let uncertainCount: Int
    let waitingHandoffs: [WaitingHandoff]

    var content: Content {
        Content(
            dominantState: dominantState,
            waitingCount: waitingCount,
            workingCount: workingCount,
            restingCount: restingCount,
            uncertainCount: uncertainCount,
            waitingHandoffs: waitingHandoffs
        )
    }

    init(
        generatedAt: Date,
        dominantState: State,
        waitingCount: Int,
        workingCount: Int,
        restingCount: Int,
        uncertainCount: Int,
        waitingHandoffs: [WaitingHandoff]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.dominantState = dominantState
        self.waitingCount = waitingCount
        self.workingCount = workingCount
        self.restingCount = restingCount
        self.uncertainCount = uncertainCount
        self.waitingHandoffs = waitingHandoffs
    }
}

enum PerchWidgetSnapshotStorage {
    static let appGroupIdentifier = "R8HXTBY3NM.com.tcballard.perch"
    static let fileName = "perch-widget-snapshot.json"
    static let widgetKind = "PerchAttentionWidget"

    static func fileURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func load(from fileURL: URL? = fileURL()) -> PerchWidgetSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(PerchWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == PerchWidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
