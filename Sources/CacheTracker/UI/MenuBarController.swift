import AppKit
import SwiftUI
import Combine

/// Standard menu bar status item hosting a rendered badge image, with a
/// popover listing sessions on click. Works the same regardless of notch
/// vs. external monitor setups.
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
        let color: NSColor
        switch worstStatus {
        case .fresh: color = .systemBlue
        case .orange: color = .systemOrange
        case .red: color = .systemRed
        }

        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let text = "\(activeSessions.count)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textOrigin = NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            )
            text.draw(at: textOrigin, withAttributes: attrs)
            return true
        }
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
