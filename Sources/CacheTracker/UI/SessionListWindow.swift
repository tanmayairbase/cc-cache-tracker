import AppKit
import SwiftUI
import os.log

private let sessionWindowLog = Logger(subsystem: "com.local.cachetracker", category: "SessionListWindow")

/// A borderless replacement for NSPopover's `show(relativeTo:of:)`.
///
/// NSPopover has a known positioning bug for LSUIElement (accessory) apps
/// when "Displays have separate Spaces" is enabled with multiple monitors:
/// it anchors to the wrong screen instead of the one the status item button
/// actually lives on. Activating the app first does not fix it. Computing
/// the button's screen rect ourselves and positioning a plain NSWindow there
/// sidesteps NSPopover's internal (buggy) placement logic entirely.
final class SessionListWindow: NSWindow {
    init(poller: Poller) {
        let size = NSSize(width: 320, height: 240)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(
            rootView: SessionListPopover(poller: poller)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting
    }

    /// Positions the window's top-left just below the given button, on the
    /// same screen the button's own window is on.
    func position(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            sessionWindowLog.notice("position(below:): button.window is nil")
            return
        }
        let buttonBoundsInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonBoundsInWindow)

        let x = buttonFrameOnScreen.midX - frame.width / 2
        let y = buttonFrameOnScreen.minY - frame.height - 4
        sessionWindowLog.notice("position(below:): buttonWindowFrame=\(buttonWindow.frame.debugDescription) buttonFrameOnScreen=\(buttonFrameOnScreen.debugDescription) computedOrigin=(\(x), \(y)) screens=\(NSScreen.screens.map { $0.frame }.map { $0.debugDescription })")
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
}
