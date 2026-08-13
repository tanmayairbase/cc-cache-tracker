import Foundation

/// Mirrors the JSON written by hooks/cache-touch.sh into
/// ~/.claude/notch-tracker/session-<hash>.json
struct SessionState: Codable, Identifiable, Equatable {
    var sessionId: String
    var cwd: String
    var transcriptPath: String
    var title: String
    var lastTouch: TimeInterval

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case title
        case lastTouch = "last_touch"
    }

    var lastTouchDate: Date {
        Date(timeIntervalSince1970: lastTouch)
    }
}

/// A SessionState merged with its local handoff override, ready for display.
struct SessionInfo: Identifiable, Equatable {
    var state: SessionState
    var handedOff: Bool

    var id: String { state.sessionId }
    var title: String { state.title }
    var cwd: String { state.cwd }

    var status: CacheStatus {
        CacheStatus.compute(lastTouch: state.lastTouchDate, handedOff: handedOff)
    }

    var done: Bool { handedOff }
}
