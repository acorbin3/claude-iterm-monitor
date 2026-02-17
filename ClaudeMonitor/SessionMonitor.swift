import Foundation
import Combine

let logFile = "/tmp/claude_monitor_debug.log"

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
}

final class SessionMonitor: ObservableObject {
    @Published var sessions: [Int32: ClaudeSession] = [:]
    @Published var shouldFlash: Bool = false

    private var pollTimer: DispatchSourceTimer?
    private var flashResetWork: DispatchWorkItem?

    private let cpuRunningThreshold: Double = 5.0
    private let cpuIdleThreshold: Double = 2.0
    private let pollInterval: TimeInterval = 2.0
    private let pollQueue = DispatchQueue(label: "com.claudemonitor.poll", qos: .utility)

    var openCount: Int { sessions.count }
    var runningCount: Int { sessions.values.filter { $0.state == .running }.count }
    var doneCount: Int { sessions.values.filter { $0.state == .recentlyCompleted }.count }

    func start() {
        debugLog("SessionMonitor.start() called")
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        pollTimer = timer
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// Called when user opens the menu — acknowledge all done sessions back to idle
    func acknowledgeDone() {
        for pid in sessions.keys {
            if sessions[pid]?.state == .recentlyCompleted {
                sessions[pid]?.state = .idle
                sessions[pid]?.lastStateChange = Date()
            }
        }
        shouldFlash = false
    }

    /// Acknowledge a single session by PID
    func acknowledgeSession(pid: Int32) {
        if sessions[pid]?.state == .recentlyCompleted {
            sessions[pid]?.state = .idle
            sessions[pid]?.lastStateChange = Date()
        }
        // Stop flashing if no more done sessions
        if doneCount == 0 {
            shouldFlash = false
        }
    }

    private func poll() {
        let currentProcesses = fetchClaudeProcesses()
        let currentPIDs = Set(currentProcesses.map { $0.pid })
        let now = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove sessions whose PID is gone
            for pid in self.sessions.keys {
                if !currentPIDs.contains(pid) {
                    self.sessions.removeValue(forKey: pid)
                }
            }

            // Update or add sessions
            for proc in currentProcesses {
                if var existing = self.sessions[proc.pid] {
                    existing.cpuPercent = proc.cpu
                    existing.tty = proc.tty

                    switch existing.state {
                    case .idle:
                        if proc.cpu > self.cpuRunningThreshold {
                            existing.state = .running
                            existing.lastStateChange = now
                        }
                    case .running:
                        if proc.cpu < self.cpuIdleThreshold {
                            existing.state = .recentlyCompleted
                            existing.lastStateChange = now
                            self.triggerFlash()
                        }
                    case .recentlyCompleted:
                        // If it starts running again, go back to running
                        if proc.cpu > self.cpuRunningThreshold {
                            existing.state = .running
                            existing.lastStateChange = now
                        }
                        // Otherwise stay as done — user hasn't acknowledged yet
                    }

                    self.sessions[proc.pid] = existing
                } else {
                    let state: SessionState = proc.cpu > self.cpuRunningThreshold ? .running : .idle
                    self.sessions[proc.pid] = ClaudeSession(
                        id: proc.pid,
                        tty: proc.tty,
                        cpuPercent: proc.cpu,
                        state: state,
                        lastStateChange: now,
                        commandName: proc.command
                    )
                }
            }

            debugLog("sessions updated: open=\(self.openCount) running=\(self.runningCount) done=\(self.doneCount)")
        }
    }

    private struct ProcessInfo {
        let pid: Int32
        let cpu: Double
        let tty: String
        let command: String
    }

    private func fetchClaudeProcesses() -> [ProcessInfo] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,pcpu,tty,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            debugLog("ERROR: ps failed to launch: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ProcessInfo] = []

        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            if parts.count < 4 { continue }

            guard let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]) else { continue }

            let tty = String(parts[2])
            let command = String(parts[3]).trimmingCharacters(in: .whitespaces)

            let basename = (command as NSString).lastPathComponent
            if basename == "claude" && !command.contains("Claude.app") {
                results.append(ProcessInfo(pid: pid, cpu: cpu, tty: tty, command: command))
            }
        }

        return results
    }

    private func triggerFlash() {
        self.shouldFlash = true
        self.flashResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.shouldFlash = false
        }
        self.flashResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }
}
