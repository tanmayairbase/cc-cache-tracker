import AppKit
import SwiftUI
import Combine
import os.log

private let menuBarLog = Logger(subsystem: "com.local.cachetracker", category: "MenuBarController")

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
    private var statusItem = NSStatusBar.system.statusItem(withLength: 32)
    private let sessionWindow: SessionListWindow
    private var cancellable: AnyCancellable?
    private let poller: Poller

    init(poller: Poller) {
        self.poller = poller
        sessionWindow = SessionListWindow(poller: poller)
        super.init()

        sessionWindow.delegate = self
        wireUpStatusItem()

        // The status item's backing window is placed by SystemUIServer over
        // IPC. When displays are added/removed/reconfigured — including a
        // monitor sleeping and waking, which is exactly what precedes this
        // bug — that item can be left describing coordinates for a screen
        // layout that no longer exists, and nothing at the NSWindow level
        // fixes it (proven: collectionBehavior/ordering tricks were
        // ineffective for 9 minutes straight; only relaunching the process
        // helped). Tearing down and recreating the NSStatusItem is the
        // in-process equivalent of that relaunch.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        updateBadgeImage(sessions: poller.sessions)
        // @Published emits on willSet, i.e. *before* the property is actually
        // mutated — reading poller.sessions inside this closure would see the
        // stale value, so use the emitted value directly instead.
        cancellable = poller.$sessions.sink { [weak self] sessions in
            self?.updateBadgeImage(sessions: sessions)
        }
    }

    private func wireUpStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleScreenChange(_ notification: Notification) {
        menuBarLog.notice("handleScreenChange: \(notification.name.rawValue) screens=\(NSScreen.screens.map { $0.frame.debugDescription })")
        rebuildStatusItem(reason: notification.name.rawValue)
    }

    /// Destroys and recreates the NSStatusItem. This forces a fresh
    /// registration with the system status bar (and a fresh backing window
    /// from SystemUIServer), which is the only thing observed to actually
    /// clear the "clicks do nothing on the external monitor" state short of
    /// relaunching the whole process.
    private func rebuildStatusItem(reason: String) {
        let oldFrame = statusItem.button?.window?.frame
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        wireUpStatusItem()
        updateBadgeImage(sessions: poller.sessions)
        menuBarLog.notice("rebuildStatusItem: reason=\(reason) oldButtonWindowFrame=\(oldFrame?.debugDescription ?? "nil") newButtonWindowFrame=\(self.statusItem.button?.window?.frame.debugDescription ?? "nil")")
    }

    /// True when the status item's backing window claims a frame that doesn't
    /// intersect any screen that currently exists — i.e. its coordinates are
    /// stale and anything positioned off them will land nowhere visible.
    private func statusItemAnchorIsStale() -> Bool {
        guard let windowFrame = statusItem.button?.window?.frame else { return true }
        return !NSScreen.screens.contains { $0.frame.intersects(windowFrame) }
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
        let eventType = NSApp.currentEvent?.type
        menuBarLog.notice("handleClick: eventType=\(eventType.map { "\($0.rawValue)" } ?? "nil")")
        if eventType == .rightMouseUp {
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
        // Self-heal before doing anything else: if the status item's
        // coordinates are stale, recreate it now rather than positioning off
        // garbage.
        if statusItemAnchorIsStale() {
            menuBarLog.notice("togglePopover: status item anchor is stale, rebuilding")
            rebuildStatusItem(reason: "stale-anchor-on-click")
        }

        // Always re-fetch the button from the (possibly just-recreated) status
        // item rather than trusting a captured reference.
        guard let button = statusItem.button else {
            menuBarLog.notice("togglePopover: no status item button")
            return
        }
        menuBarLog.notice("togglePopover: isVisible=\(self.sessionWindow.isVisible) buttonScreen=\(button.window?.screen?.frame.debugDescription ?? "nil") mouse=\(NSEvent.mouseLocation.debugDescription)")
        if sessionWindow.isVisible {
            sessionWindow.orderOut(nil)
        } else {
            let targetScreen = sessionWindow.position(below: button)
            NSApp.activate(ignoringOtherApps: true)
            sessionWindow.orderFrontRegardless()
            sessionWindow.makeKey()
            menuBarLog.notice("togglePopover: after show frame=\(self.sessionWindow.frame.debugDescription) isVisible=\(self.sessionWindow.isVisible) isOnActiveSpace=\(self.sessionWindow.isOnActiveSpace) targetScreen=\(targetScreen?.frame.debugDescription ?? "nil") windowScreen=\(self.sessionWindow.screen?.frame.debugDescription ?? "nil")")

            // If, after all that, the window still isn't on the active Space,
            // the process-level status bar registration is the thing that's
            // wrong — not this window. Rebuild the status item and retry once.
            if !sessionWindow.isOnActiveSpace {
                menuBarLog.notice("togglePopover: still not on active space after show, rebuilding status item and retrying")
                rebuildStatusItem(reason: "not-on-active-space")
                if let retryButton = statusItem.button {
                    sessionWindow.orderOut(nil)
                    sessionWindow.position(below: retryButton)
                    sessionWindow.orderFrontRegardless()
                    sessionWindow.makeKey()
                    menuBarLog.notice("togglePopover: after retry frame=\(self.sessionWindow.frame.debugDescription) isVisible=\(self.sessionWindow.isVisible) isOnActiveSpace=\(self.sessionWindow.isOnActiveSpace) windowScreen=\(self.sessionWindow.screen?.frame.debugDescription ?? "nil")")
                }
            }
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
