# Cowork Supervisor Plugin

Monitor, manage, and recover multi-agent teams in Claude Code and Claude Desktop.

## Features

- **Log-based agent detection** — monitors `cowork_vm_node.log` for Spawn/Exit events (not screenshots)
- **Auto-nudge** — when agent stops, automatically sends message to Claude Desktop to continue
- **Crash recovery** — detects stuck agents and re-dispatches with preserved context
- **Resource protection** — monitors swap/memory pressure, auto-reduces parallelism when needed
- **Progress snapshots** — periodic state saves for recovery after interruptions
- **Background watchdog script** — `cowork_supervisor_v2.sh` runs independently for up to 8 hours

## Requirements

- Claude Code CLI or Claude Desktop with Cowork
- Python 3 with `pyautogui` (for GUI nudging)
- macOS (uses `osascript`, `cliclick`, `pbcopy`)

## Usage

### Slash Command
```
/supervisor Build a REST API with tests
```

### Trigger Phrases
- "启动 Supervisor" / "监控 Cowork" / "开始监工"
- "Start supervisor" / "Monitor cowork"

### Background Watchdog
```bash
# Start 8-hour monitoring
bash scripts/cowork_supervisor_v2.sh &

# View live log
tail -f /tmp/cowork_supervisor_v2.log

# Stop
kill $(cat /tmp/cowork_supervisor_v2.pid)
```

## How Detection Works

### V2: Log-based (reliable)
Monitors `~/Library/Logs/Claude/cowork_vm_node.log`:
- `"Spawn succeeded"` → agent is running
- `"Exited, code=0"` → agent stopped → auto-nudge
- `"active=0"` → no active processes → confirmed idle

### V1: Screenshot comparison (deprecated, unreliable)
~~Compares screenshot MD5 hashes~~ — fails on macOS because clock, notifications, and cursor blinking cause screenshots to always differ.

## How Nudging Works

When agent is detected as idle:
1. Message copied to clipboard via `pbcopy`
2. `pyautogui.click()` focuses Claude Desktop reply box (Electron WebView requires this)
3. `osascript` pastes (`Cmd+V`) and sends (`Enter`)

**Known limitations:**
- `keystroke` cannot type Chinese directly (IME garbles it) — use clipboard paste
- `pyautogui.hotkey('command', 'v')` unreliable on macOS — use osascript instead
- AppleScript `click at {x,y}` doesn't work on Electron WebView — use pyautogui

## Resource Guidelines

| Machine RAM | Safe Parallel Agents |
|-------------|---------------------|
| 8GB | 1-2 |
| 16GB | 2-3 |
| 32GB+ | 4-5 |

## Installation

```bash
git clone https://github.com/ChristopherCC-Liu/superchris.git
cp -r superchris ~/.claude/plugins/local/cowork-supervisor

# Install pyautogui if needed
pip install pyautogui
```

## License

MIT
