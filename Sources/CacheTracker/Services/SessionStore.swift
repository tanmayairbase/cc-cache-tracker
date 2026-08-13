import Foundation

/// Reads the per-session JSON state files written by hooks/cache-touch.sh and
/// merges them with a local handoffs.json override file. Hook files are
/// never written to or deleted by this app. handoffs.json is owned entirely
/// by this app; hooks never touch it, so writes here are safe from races
/// with hook writes.
final class SessionStore {
    private let stateDir: URL
    private let handoffsFile: URL

    init(baseDir: URL? = nil) {
        let base = baseDir ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cache-tracker", isDirectory: true)
        self.stateDir = base
        self.handoffsFile = base.appendingPathComponent("handoffs.json")
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    /// handoffs.json maps session_id -> epoch seconds at which it was marked done.
    private func loadHandoffs() -> [String: TimeInterval] {
        guard let data = try? Data(contentsOf: handoffsFile) else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    private func saveHandoffs(_ handoffs: [String: TimeInterval]) {
        guard let data = try? JSONEncoder().encode(handoffs) else { return }
        try? data.write(to: handoffsFile, options: .atomic)
    }

    private func loadStates() -> [SessionState] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: stateDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "handoffs.json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(SessionState.self, from: data)
            }
    }

    /// Returns all sessions with activity in the last 24h, merged with
    /// handoff overrides. A handoff override is ignored (and pruned) once
    /// the session's last_touch advances past the time it was marked done —
    /// i.e. any new activity silently reopens it.
    func activeSessions() -> [SessionInfo] {
        let states = loadStates()
        var handoffs = loadHandoffs()
        var handoffsChanged = false
        let now = Date()

        var result: [SessionInfo] = []
        for state in states {
            let age = now.timeIntervalSince(state.lastTouchDate)
            if age > CacheThresholds.staleHideSeconds {
                continue
            }

            var handedOff = false
            if let markedAt = handoffs[state.sessionId] {
                if state.lastTouch > markedAt {
                    // New activity since it was marked done: silently reopen.
                    handoffs.removeValue(forKey: state.sessionId)
                    handoffsChanged = true
                } else {
                    handedOff = true
                }
            }

            result.append(SessionInfo(state: state, handedOff: handedOff))
        }

        if handoffsChanged {
            saveHandoffs(handoffs)
        }

        return result.sorted { $0.state.lastTouch > $1.state.lastTouch }
    }

    /// Marks a session as done/handed-off "now". Ignored by future polls
    /// until the underlying state file's last_touch advances past this
    /// moment.
    func markHandedOff(sessionId: String) {
        var handoffs = loadHandoffs()
        handoffs[sessionId] = Date().timeIntervalSince1970
        saveHandoffs(handoffs)
    }
}
