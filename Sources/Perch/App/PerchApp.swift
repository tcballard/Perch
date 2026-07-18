import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = PerchAppModel.shared
        model.roster.start()
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: "desktopCompanionEnabled") == nil
            ? true
            : defaults.bool(forKey: "desktopCompanionEnabled")
        model.desktopCompanion.setVisible(isEnabled)
    }
}

@MainActor
final class PerchAppModel {
    static let shared = PerchAppModel()

    let roster: RosterCoordinator
    let desktopCompanion: DesktopCompanionController

    private init() {
        let roster = RosterCoordinator(
            adapters: PerchApp.adapters,
            pollingInterval: .seconds(1),
            widgetSnapshotPublisher: WidgetSnapshotPublisher()
        )
        self.roster = roster
        desktopCompanion = DesktopCompanionController(roster: roster)
    }
}

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = PerchAppModel.shared
    @AppStorage("desktopCompanionEnabled") private var desktopCompanionEnabled = true

    fileprivate static var adapters: [any AgentProviderAdapter] {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return [] }
        if environment["PERCH_USE_MOCK"] == "1" { return [ScriptedMockAdapter()] }
        return [CodexAdapter(), ClaudeDesktopAdapter()]
    }

    var body: some Scene {
        MenuBarExtra {
            PerchPanelView(
                roster: model.roster,
                desktopCompanionEnabled: $desktopCompanionEnabled,
                setDesktopCompanionVisible: model.desktopCompanion.setVisible
            )
        } label: {
            PerchStatusLabel(
                waitingCount: AttentionPresentation(sessions: model.roster.sessions).waitingCount,
                dominantState: AttentionPresentation(sessions: model.roster.sessions).dominantState
            )
        }
        .menuBarExtraStyle(.window)
    }
}
