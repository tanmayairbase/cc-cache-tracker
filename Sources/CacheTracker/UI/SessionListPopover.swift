import SwiftUI

struct SessionListPopover: View {
    @ObservedObject var poller: Poller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Claude Code Sessions")
                .font(.headline)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 4)

            if poller.sessions.isEmpty {
                Text("No active sessions")
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ForEach(poller.sessions) { info in
                    SessionRow(info: info) {
                        poller.markHandedOff(sessionId: info.id)
                    }
                    Divider()
                }
            }
        }
        .frame(width: 320)
        .padding(.bottom, 8)
    }
}

private struct SessionRow: View {
    let info: SessionInfo
    let onMarkDone: () -> Void

    private var statusColor: Color {
        switch info.status {
        case .fresh: return .blue
        case .orange: return .orange
        case .red: return .red
        }
    }

    private var relativeTime: String {
        let elapsed = Int(Date().timeIntervalSince(info.state.lastTouchDate))
        if elapsed < 60 { return "just now" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h ago" : "\(hours)h \(remainingMinutes)m ago"
    }

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 13, weight: .medium))
                Text(info.cwd)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onMarkDone) {
                Image(systemName: info.done ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundColor(info.done ? .green : .secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(info.done)
            .focusEffectDisabled()
            .help(info.done ? "Handed off" : "Mark Done / Handed off")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
