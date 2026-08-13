import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("NotificationService: authorization error \(error)")
            } else {
                print("NotificationService: authorization granted=\(granted)")
            }
        }
    }

    func notifyExpiringSoon(sessionTitle: String, cwd: String) {
        let dirName = (cwd as NSString).lastPathComponent
        let content = UNMutableNotificationContent()
        content.title = "Cache expiring soon"
        content.body = "Cache expiring in 15m for '\(sessionTitle)' (\(dirName))"
        content.sound = .default
        post(content)
    }

    func notifyExpiringImminently(sessionTitle: String, cwd: String) {
        let dirName = (cwd as NSString).lastPathComponent
        let content = UNMutableNotificationContent()
        content.title = "Cache expiring imminently"
        content.body = "Cache expiring in 5m for '\(sessionTitle)' (\(dirName))"
        content.sound = .default
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationService: failed to add notification \(error)")
            }
        }
    }
}
