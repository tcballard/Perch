import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var roster = RosterCoordinator(
        adapters: ProcessInfo.processInfo.environment["PERCH_USE_MOCK"] == "1"
            ? [ScriptedMockAdapter()]
            : [CodexAdapter(), ClaudeDesktopAdapter()],
        pollingInterval: .seconds(1)
    )

    var body: some Scene {
        MenuBarExtra {
            PerchPanelView(roster: roster)
        } label: {
            PerchStatusLabel(waitingCount: roster.waitingCount)
                .task { roster.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
