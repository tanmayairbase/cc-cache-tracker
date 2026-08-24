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
final class SessionListWindow: NSPanel {
    init(poller: Poller) {
        let size = NSSize(width: 320, height: 240)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        // NOT `.canJoinAllSpaces`. That behavior is evaluated when the window is
        // registered with the WindowServer, so a Space created *later* — e.g.
        // the new managed Space an external display gets after sleep/wake with
        // "Displays have separate Spaces" on — never includes this window, and
        // it is then permanently `isVisible == true, isOnActiveSpace == false`.
        // `.moveToActiveSpace` instead asks the WindowServer to relocate the
        // window to whatever Space is active each time the app is activated,
        // which has no stale-Space-set failure mode. This is the same
        // collection behavior Ice (open source menu bar manager) uses for its
        // click-to-open bar panel.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]

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
    /// screen the click actually happened on.
    ///
    /// The status item's backing window is owned by the system (SystemUIServer
    /// drives its placement over IPC) and its reported frame has been observed
    /// to go stale — after a display sleep/wake or Space reconfiguration it can
    /// still describe coordinates on a screen geometry that no longer exists.
    /// Positioning off it blindly then puts this window at coordinates that
    /// belong to no current screen, so it is "visible" but nowhere the user can
    /// see it. So: derive the anchor from the button, but validate it against
    /// the live NSScreen list and fall back to the screen the cursor is on.
    @discardableResult
    func position(below button: NSStatusBarButton) -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(mouse) }

        var anchor: NSRect?
        if let buttonWindow = button.window {
            let buttonBoundsInWindow = button.convert(button.bounds, to: nil)
            anchor = buttonWindow.convertToScreen(buttonBoundsInWindow)
        } else {
            sessionWindowLog.notice("position(below:): button.window is nil")
        }

        // Is the anchor actually on a screen that currently exists, and is it
        // the same screen the user just clicked on? Either being false means
        // the status item's coordinates are stale/wrong.
        let anchorScreen = anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.intersects(rect) }
        }
        let anchorIsStale = anchorScreen == nil || (mouseScreen != nil && anchorScreen !== mouseScreen)

        let targetScreen = mouseScreen ?? anchorScreen ?? NSScreen.main
        var anchorRect = anchor ?? .zero
        if anchorIsStale, let screen = targetScreen {
            // Rebuild the anchor from scratch: the cursor's x, pinned just
            // under this screen's menu bar.
            let menuBarBottom = screen.visibleFrame.maxY
            anchorRect = NSRect(x: mouse.x - 11, y: menuBarBottom, width: 22, height: 22)
        }

        var origin = NSPoint(
            x: anchorRect.midX - frame.width / 2,
            y: anchorRect.minY - frame.height - 4
        )

        // Final clamp so the window can never land outside the target screen.
        if let visible = targetScreen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - frame.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - frame.height)
        }

        sessionWindowLog.notice("""
            position(below:): buttonWindowFrame=\(button.window?.frame.debugDescription ?? "nil") \
            rawAnchor=\(anchor?.debugDescription ?? "nil") anchorIsStale=\(anchorIsStale) \
            mouse=\(mouse.debugDescription) \
            mouseScreen=\(mouseScreen?.frame.debugDescription ?? "nil") \
            anchorScreen=\(anchorScreen?.frame.debugDescription ?? "nil") \
            targetScreen=\(targetScreen?.frame.debugDescription ?? "nil") \
            finalOrigin=\(origin.debugDescription) \
            screens=\(NSScreen.screens.map { $0.frame.debugDescription })
            """)
        setFrameOrigin(origin)
        return targetScreen
    }

    override var canBecomeKey: Bool { true }
}
