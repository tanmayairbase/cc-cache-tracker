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
            button.action = #selector(togglePopover)
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

        // App glyph, tinted to match the menu bar's current label color so
        // it reads correctly in both light and dark menu bars. A template
        // image would ignore the tint and render as a monochrome mask, so
        // tint a copy the same way the app icon does: sourceAtop confined
        // to the glyph's own bitmap.
        if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let glyph = symbol.withSymbolConfiguration(config)!

            let tinted = NSImage(size: glyph.size)
            tinted.lockFocus()
            glyph.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSColor.labelColor.setFill()
            NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
            tinted.unlockFocus()

            let origin = NSPoint(x: 0, y: (size.height - tinted.size.height) / 2)
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
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

    @objc private func togglePopover() {
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
