import Foundation
import Combine

/// Polls SessionStore every 60s, recomputes statuses, and fires a
/// notification only on a fresh->orange transition per session_id (not on
/// every poll while orange, not on orange->red, not for a new session that
/// enters already-orange).
final class Poller: ObservableObject {
    @Published private(set) var sessions: [SessionInfo] = []

    private let store: SessionStore
    private let notificationService: NotificationService
    private var timer: Timer?
    private var previousStatuses: [String: CacheStatus] = [:]

    init(store: SessionStore = SessionStore(), notificationService: NotificationService = .shared) {
        self.store = store
        self.notificationService = notificationService
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markHandedOff(sessionId: String) {
        store.markHandedOff(sessionId: sessionId)
        poll()
    }

    func poll() {
        let newSessions = store.activeSessions()

        for info in newSessions {
            let previous = previousStatuses[info.id]
            if previous == .fresh && info.status == .orange {
                notificationService.notifyExpiringSoon(sessionTitle: info.title, cwd: info.cwd)
            }
            previousStatuses[info.id] = info.status
        }

        // Drop tracked statuses for sessions no longer active (aged out or gone).
        let activeIds = Set(newSessions.map { $0.id })
        previousStatuses = previousStatuses.filter { activeIds.contains($0.key) }

        self.sessions = newSessions
    }
}
