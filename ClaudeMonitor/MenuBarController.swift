import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var monitor: SessionMonitor
    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?
    private var flashOn = false
    private var ttyToTabName: [String: String] = [:]
    private let refreshQueue = DispatchQueue(label: "com.claudemonitor.tabnames", qos: .utility)

    init(monitor: SessionMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupObservers()
        updateDisplay()
        refreshTabNamesAsync()
        buildMenu()
    }

    private func setupObservers() {
        monitor.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
                self?.buildMenu()
            }
            .store(in: &cancellables)

        monitor.$shouldFlash
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldFlash in
                if shouldFlash {
                    self?.startFlashing()
                } else {
                    self?.stopFlashing()
                }
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        guard let button = statusItem.button else { return }

        let text = "C: \(monitor.openCount) | R: \(monitor.runningCount) | D: \(monitor.doneCount)"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        ]

        if flashOn {
            let flashAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.systemOrange
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: flashAttrs)
        } else {
            button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        }
    }

    private func startFlashing() {
        flashTimer?.invalidate()
        flashOn = true
        updateDisplay()

        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.flashOn.toggle()
            self.updateDisplay()
        }
    }

    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
        flashOn = false
        updateDisplay()
    }

    /// Refresh tab names on a background thread, then update menu on main
    private func refreshTabNamesAsync() {
        refreshQueue.async { [weak self] in
            let mapping = Self.fetchTabNames()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ttyToTabName = mapping
                self.buildMenu()
                debugLog("Tab names refreshed async: \(mapping.count) entries")
            }
        }
    }

    /// Query iTerm2 for a mapping of ttyXXX → tab title using the Python API
    /// This gets the actual tab title (autoNameFormat) which reflects user-set names
    private static func fetchTabNames() -> [String: String] {
        let pythonScript = """
        import iterm2, asyncio
        async def main():
            connection = await iterm2.Connection.async_create()
            app = await iterm2.async_get_app(connection)
            for window in app.windows:
                for tab in window.tabs:
                    tab_title = await tab.async_get_variable('title')
                    for session in tab.sessions:
                        tty = await session.async_get_variable('tty')
                        short_tty = tty.replace('/dev/', '')
                        print(f'{short_tty}||{tab_title}')
        asyncio.run(main())
        """

        let process = Process()
        let pipe = Pipe()

        // Find python3 with iterm2 module — check common paths
        let pythonPaths = [
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        guard let pythonPath = pythonPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            debugLog("ERROR: no python3 found")
            return [:]
        }
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", pythonScript]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            debugLog("ERROR: python3 failed to launch: \(error)")
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var mapping: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "||")
            if parts.count == 2 {
                let tty = parts[0].trimmingCharacters(in: .whitespaces)
                let title = parts[1].trimmingCharacters(in: .whitespaces)
                if !tty.isEmpty && !title.isEmpty {
                    mapping[tty] = cleanTabTitle(title)
                }
            }
        }

        return mapping
    }

    /// Clean up the tab title — remove leading status icons like ✳ ⠐
    private static func cleanTabTitle(_ raw: String) -> String {
        var title = raw
        while let first = title.unicodeScalars.first,
              !first.properties.isAlphabetic || !first.isASCII {
            title = String(title.dropFirst())
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Claude Sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let sortedSessions = monitor.sessions.values.sorted { $0.pid < $1.pid }

        if sortedSessions.isEmpty {
            let noSessions = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            noSessions.isEnabled = false
            menu.addItem(noSessions)
        } else {
            for session in sortedSessions {
                let tabName = ttyToTabName[session.tty] ?? session.tty
                let title = "\(session.stateEmoji) \(tabName) — \(session.stateLabel) (\(session.durationSinceStateChange))"
                let item = NSMenuItem(title: title, action: #selector(sessionClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.tty
                item.tag = Int(session.pid)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if monitor.doneCount > 0 {
            let clearItem = NSMenuItem(title: "Clear Done", action: #selector(clearDone), keyEquivalent: "r")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func clearDone() {
        monitor.acknowledgeDone()
    }

    @objc private func sessionClicked(_ sender: NSMenuItem) {
        guard let tty = sender.representedObject as? String else { return }
        let pid = Int32(sender.tag)

        // Mark this specific session as acknowledged
        monitor.acknowledgeSession(pid: pid)

        // Switch to that iTerm tab
        activateITermSession(tty: tty)
    }

    private func activateITermSession(tty: String) {
        let devicePath = "/dev/\(tty)"
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(devicePath)" then
                            tell w to select t
                            tell t to select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                debugLog("AppleScript error: \(error)")
            }
        }
    }

    // MARK: - NSMenuDelegate

    /// When the user opens the dropdown, refresh tab names in background
    func menuWillOpen(_ menu: NSMenu) {
        refreshTabNamesAsync()
    }
}
