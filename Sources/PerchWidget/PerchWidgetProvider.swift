import Foundation
import WidgetKit

struct PerchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PerchWidgetSnapshot?
    let isStale: Bool
}

struct PerchWidgetProvider: TimelineProvider {
    private static let staleInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> PerchWidgetEntry {
        PerchWidgetEntry(date: .now, snapshot: .preview, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PerchWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entry(at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PerchWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        let nextRefresh = now.addingTimeInterval(Self.staleInterval)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(at date: Date) -> PerchWidgetEntry {
        let snapshot = PerchWidgetSnapshotStorage.load()
        let stale = snapshot.map { date.timeIntervalSince($0.generatedAt) > Self.staleInterval } ?? true
        return PerchWidgetEntry(date: date, snapshot: snapshot, isStale: stale)
    }
}

private extension PerchWidgetSnapshot {
    static var preview: PerchWidgetSnapshot {
        PerchWidgetSnapshot(
            generatedAt: .now,
            dominantState: .waiting,
            waitingCount: 2,
            workingCount: 3,
            restingCount: 2,
            uncertainCount: 1,
            waitingHandoffs: [
                WaitingHandoff(
                    projectName: "checkout-flow",
                    action: "Permission required",
                    waitingSince: .now.addingTimeInterval(-7 * 60),
                    providerName: "Codex",
                    focusURL: URL(string: "codex://threads/preview")
                ),
                WaitingHandoff(
                    projectName: "refactor-auth",
                    action: "Input required",
                    waitingSince: .now.addingTimeInterval(-3 * 60),
                    providerName: "Claude",
                    focusURL: nil
                )
            ]
        )
    }
}
