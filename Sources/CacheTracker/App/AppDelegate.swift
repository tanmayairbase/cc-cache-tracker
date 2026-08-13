import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let poller = Poller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement app: no Dock icon, no regular window.
        NSApp.setActivationPolicy(.accessory)

        NotificationService.shared.requestAuthorization()

        menuBar = MenuBarController(poller: poller)

        poller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller.stop()
    }
}
