import AppIntents
import Foundation
import WidgetKit

enum PerchWidgetFilter: String, AppEnum, CaseIterable, Sendable {
    case all
    case waiting
    case working
    case resting
    case uncertain

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Session state")
    static let caseDisplayRepresentations: [PerchWidgetFilter: DisplayRepresentation] = [
        .all: "All sessions",
        .waiting: "Waiting",
        .working: "Working",
        .resting: "Resting",
        .uncertain: "Uncertain"
    ]
}

enum PerchWidgetFilterPreference {
    private static let key = "widgetSessionFilter"

    static var current: PerchWidgetFilter {
        get {
            guard let value = UserDefaults(suiteName: PerchWidgetSnapshotStorage.appGroupIdentifier)?.string(forKey: key),
                  let filter = PerchWidgetFilter(rawValue: value)
            else { return .all }
            return filter
        }
        set {
            UserDefaults(suiteName: PerchWidgetSnapshotStorage.appGroupIdentifier)?.set(newValue.rawValue, forKey: key)
        }
    }
}

struct SetPerchWidgetFilterIntent: AppIntent {
    static let title: LocalizedStringResource = "Filter Perch sessions"
    static let description = IntentDescription("Shows sessions with the selected state in the Perch widget.")
    static let openAppWhenRun = false

    @Parameter(title: "State")
    var filter: PerchWidgetFilter

    init() {}

    init(filter: PerchWidgetFilter) {
        self.filter = filter
    }

    func perform() async throws -> some IntentResult {
        PerchWidgetFilterPreference.current = filter
        WidgetCenter.shared.reloadTimelines(ofKind: PerchWidgetSnapshotStorage.widgetKind)
        return .result()
    }
}
