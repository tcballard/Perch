import AppKit
import SwiftUI

@MainActor
final class DesktopCompanionController {
    private let roster: RosterCoordinator
    private var panel: NSPanel?

    init(roster: RosterCoordinator) {
        self.roster = roster
    }

    func setVisible(_ isVisible: Bool) {
        isVisible ? show() : hide()
    }

    func show() {
        let panel = panel ?? makePanel()
        panel.orderBack(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 336, height: 272)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Perch Desktop Companion"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Desktop-icon levels can be buried beneath Finder's desktop host.
        // A normal, non-activating panel ordered back remains visible on a
        // clear desktop while ordinary application windows cover it.
        panel.level = .normal
        panel.contentViewController = NSHostingController(
            rootView: DesktopPerchView(roster: roster) { [weak self] in
                UserDefaults.standard.set(false, forKey: "desktopCompanionEnabled")
                self?.hide()
            }
        )
        panel.setContentSize(size)
        panel.setFrameAutosaveName("PerchDesktopCompanion")

        if !panel.setFrameUsingName("PerchDesktopCompanion"),
           let visibleFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: visibleFrame.minX + 24,
                y: visibleFrame.maxY - size.height - 24
            )
            panel.setFrameOrigin(origin)
        }

        self.panel = panel
        return panel
    }
}
