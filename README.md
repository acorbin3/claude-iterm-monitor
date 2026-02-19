# Claude Monitor

A native macOS menu bar app that monitors Claude Code CLI terminal sessions in iTerm2.

## What It Does

Sits in your macOS status bar and shows real-time counts of your Claude Code sessions:

```
C: 12 | R: 2 | D: 1
```

- **C** (Count) — Total open Claude CLI sessions
- **R** (Running) — Sessions actively generating a response (CPU > 5%)
- **D** (Done) — Sessions that just finished responding, waiting for you to check them

When a session finishes responding, the menu bar flashes orange for 5 seconds.

## Menu Dropdown

Click the status bar item to see all sessions with their iTerm2 tab titles:

```
Claude Sessions
─────────────────────────
⏸ My Project — Idle (2m)
🔄 API Server — Running (5s)
✅ Bug Fix — Done (12s)
─────────────────────────
Quit                  ⌘Q
```

Click any session to switch directly to that iTerm2 tab. Clicking a "Done" session also acknowledges it, decrementing the D count.

## Detection

- Polls `ps -eo pid,pcpu,tty,comm` every 2 seconds
- Filters for processes where the command basename is `claude` (excludes Claude.app desktop)
- Tracks CPU% per PID to determine state:
  - **Idle**: CPU < 5%
  - **Running**: CPU > 5%
  - **Done**: CPU dropped from > 5% to < 2% (finished generating)

## Requirements

- macOS 13+ (Ventura or later)
- Swift 5.9+
- iTerm2 (for tab title display and tab switching)
- Grant Automation permission for ClaudeMonitor to control iTerm2 when prompted

## Setup

### Quick Setup

Run the setup script to install dependencies and enable the iTerm2 Python API:

```bash
./setup.sh
```

### Manual Setup

The menu dropdown shows iTerm2 tab names using the iTerm2 Python API. To enable this:

1. **Install the `iterm2` Python package:**

   ```bash
   pip3 install iterm2
   ```

2. **Enable the iTerm2 Python API:**

   Go to iTerm2 > Settings > General > Magic > check **Enable Python API**

   Or run:

   ```bash
   defaults write com.googlecode.iterm2 EnableAPIServer -bool true
   ```

   Then restart iTerm2 for the setting to take effect.

Without these, the app still works but sessions will show TTY names (e.g. `ttys004`) instead of tab titles.

## Build & Run

```bash
swift build
swift run
```

## Project Structure

```
ClaudeMonitor/
├── ClaudeMonitorApp.swift    # App entry point, NSApplication setup (no dock icon)
├── SessionMonitor.swift      # Process polling, CPU tracking, state machine
├── MenuBarController.swift   # NSStatusItem, flash animation, menu with iTerm2 integration
└── Models.swift              # ClaudeSession struct, SessionState enum
```

## Debug Log

A debug log is written to `/tmp/claude_monitor_debug.log` for troubleshooting.
