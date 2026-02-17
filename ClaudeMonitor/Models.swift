import Foundation

enum SessionState: String {
    case idle
    case running
    case recentlyCompleted
}

struct ClaudeSession: Identifiable {
    let id: Int32  // PID
    var tty: String
    var cpuPercent: Double
    var state: SessionState
    var lastStateChange: Date
    var commandName: String

    var pid: Int32 { id }

    var stateEmoji: String {
        switch state {
        case .idle: return "⏸"
        case .running: return "🔄"
        case .recentlyCompleted: return "✅"
        }
    }

    var stateLabel: String {
        switch state {
        case .idle: return "Idle"
        case .running: return "Running"
        case .recentlyCompleted: return "Done"
        }
    }

    var durationSinceStateChange: String {
        let elapsed = Date().timeIntervalSince(lastStateChange)
        if elapsed < 60 {
            return "\(Int(elapsed))s"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        } else {
            return "\(Int(elapsed / 3600))h"
        }
    }
}
