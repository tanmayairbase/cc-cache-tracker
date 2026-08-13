import Foundation

/// Hardcoded thresholds per the 1-hour org cache TTL (see handoff doc section 1/9).
/// No settings UI / UserDefaults plumbing for v1 — these are intentionally fixed.
enum CacheThresholds {
    static let freshToOrangeSeconds: TimeInterval = 45 * 60
    static let orangeToRedSeconds: TimeInterval = 60 * 60
    /// Sessions with no activity for this long are excluded from the active list.
    static let staleHideSeconds: TimeInterval = 24 * 60 * 60
}

enum CacheStatus: String, Comparable {
    case fresh
    case orange
    case red

    private var rank: Int {
        switch self {
        case .fresh: return 0
        case .orange: return 1
        case .red: return 2
        }
    }

    static func < (lhs: CacheStatus, rhs: CacheStatus) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Computes status from elapsed time since last activity. A session marked
    /// handed off/done is treated as fresh for badge/notification purposes as
    /// long as it stays handed off (SessionStore clears the override the
    /// moment new activity is recorded, so this flag only applies while truly
    /// idle-and-acknowledged).
    static func compute(lastTouch: Date, handedOff: Bool) -> CacheStatus {
        if handedOff {
            return .fresh
        }
        let elapsed = Date().timeIntervalSince(lastTouch)
        if elapsed >= CacheThresholds.orangeToRedSeconds {
            return .red
        } else if elapsed >= CacheThresholds.freshToOrangeSeconds {
            return .orange
        } else {
            return .fresh
        }
    }
}
