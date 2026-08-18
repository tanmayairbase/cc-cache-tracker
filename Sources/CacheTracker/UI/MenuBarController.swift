import AppKit
import SwiftUI
import Combine

/// Standard menu bar status item hosting a rendered badge image, with a
/// popover listing sessions on click. Works the same regardless of
/// display/monitor setup.
///
/// The badge is rendered to an NSImage and set as the button's image rather
/// than embedding a SwiftUI view as a subview — the subview approach fights
/// the status bar's own layout of the button and throws off the coordinate
/// space NSPopover uses for `show(relativeTo:of:)`, causing the popover to
/// appear far from the button instead of anchored just below it.
final class MenuBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 32)
    private let sessionWindow: SessionListWindow
    private var cancellable: AnyCancellable?

    init(poller: Poller) {
        sessionWindow = SessionListWindow(poller: poller)
        super.init()

        sessionWindow.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateBadgeImage(sessions: poller.sessions)
        // @Published emits on willSet, i.e. *before* the property is actually
        // mutated — reading poller.sessions inside this closure would see the
        // stale value, so use the emitted value directly instead.
        cancellable = poller.$sessions.sink { [weak self] sessions in
            self?.updateBadgeImage(sessions: sessions)
        }
    }

    private func updateBadgeImage(sessions: [SessionInfo]) {
        let activeSessions = sessions.filter { !$0.done }
        let worstStatus = activeSessions.map(\.status).max() ?? .fresh
        let statusColor: NSColor
        switch worstStatus {
        case .fresh: statusColor = .systemBlue
        case .orange: statusColor = .systemOrange
        case .red: statusColor = .systemRed
        }

        let size = NSSize(width: 22, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()

        // Same colored background as the app icon (not tinted to the menu
        // bar's label color) so it stays recognizable/colorful rather than
        // going flat black-and-white like a template image would.
        let iconSize: CGFloat = 18
        let iconOrigin = NSPoint(x: 0, y: (size.height - iconSize) / 2)
        let bgRect = NSRect(origin: iconOrigin, size: NSSize(width: iconSize, height: iconSize))
        let claudeOrange = NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1.0)
        claudeOrange.setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: iconSize * 0.22, yRadius: iconSize * 0.22).fill()

        if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize * 0.5, weight: .semibold)
            let glyph = symbol.withSymbolConfiguration(config)!

            let origin = NSPoint(
                x: bgRect.midX - glyph.size.width / 2,
                y: bgRect.midY - glyph.size.height / 2
            )
            NSColor.black.set()
            glyph.isTemplate = true
            glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Plain colored status dot, no count, in the bottom-right corner.
        let dotSize: CGFloat = 8
        let dotRect = NSRect(x: size.width - dotSize, y: 0, width: dotSize, height: dotSize)
        statusColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        image.unlockFocus()
        image.isTemplate = false
        statusItem.button?.image = image
    }

    @objc private func handleClick() {
        // NSApp.currentEvent can come back nil for the click that triggered
        // this very action — observed after a status item's screen has been
        // idle for a while (e.g. an external monitor that hasn't been
        // interacted with recently). Treat that as a left click rather than
        // silently no-op'ing, otherwise the popover just fails to appear.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        sessionWindow.orderOut(nil)
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit CacheTracker", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if sessionWindow.isVisible {
            sessionWindow.orderOut(nil)
        } else {
            sessionWindow.position(below: button)
            NSApp.activate(ignoringOtherApps: true)
            sessionWindow.makeKeyAndOrderFront(nil)
            // Prevent AppKit from auto-assigning first responder to the
            // first key-view-eligible control (the row menu button), which
            // otherwise shows a native focus ring on it as soon as the
            // window becomes key.
            sessionWindow.makeFirstResponder(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        sessionWindow.orderOut(nil)
    }
}
