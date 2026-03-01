# Cowork Supervisor Plugin

Monitor, manage, and auto-recover multi-agent teams in Claude Code and Claude Desktop.

## Features

### V3 (Latest) — Self-Healing Supervisor
- **Auto-restart Claude Desktop** — detects crashes, gracefully restarts (up to 5 attempts)
- **VM health monitoring** — detects Cowork VM death, waits or restarts as needed
- **503/504 detection** — recognizes claude.ai service outages, pauses nudging during downtime
- **OOM recovery** — detects `oom=true` kills, auto-frees memory before retry
- **Swap auto-relief** — kills Chrome tabs when swap exceeds thresholds (7GB warn, 9GB critical)
- **Memory pressure monitoring** — preemptive cleanup when free memory < 10%
- **macOS notifications** — alerts via Notification Center with sound on anomalies
- **All V2 features** — log-based detection, auto-nudge, progress tracking

### V2 — Log-Based Detection
- **Log-based agent detection** — monitors `cowork_vm_node.log` for Spawn/Exit events
- **Auto-nudge** — when agent stops, sends message to Claude Desktop to continue
- **Background watchdog** — runs independently for up to 8 hours

### Core
- **Crash recovery** — detects stuck agents and re-dispatches with preserved context
- **Resource protection** — monitors swap/memory pressure, auto-reduces parallelism
- **Progress snapshots** — periodic state saves for recovery after interruptions

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

### Background Watchdog (V3 recommended)
```bash
# Start 8-hour self-healing monitoring
bash scripts/cowork_supervisor_v3.sh &

# View current status (updates every round)
cat /tmp/cowork_status.txt

# Watch periodic reports (updates every 5 rounds / ~6 min)
tail -f /tmp/cowork_report.txt

# View full debug log
tail -f /tmp/cowork_supervisor_v3.log

# Stop
kill $(cat /tmp/cowork_supervisor_v3.pid)
```

### V2 (monitoring + nudge only)
```bash
bash scripts/cowork_supervisor_v2.sh &
tail -f /tmp/cowork_supervisor_v2.log
```

## Reporting Mechanism

V3 provides three layers of continuous reporting:

| Channel | File / Method | Frequency | Use Case |
|---------|--------------|-----------|----------|
| **Real-time status** | `/tmp/cowork_status.txt` | Every round (~75s) | Quick check: `cat /tmp/cowork_status.txt` |
| **Periodic report** | `/tmp/cowork_report.txt` | Every 5 rounds (~6min) | Timeline view: `tail -f /tmp/cowork_report.txt` |
| **macOS notification** | Notification Center | Every 5 rounds + on alerts | Passive monitoring, no terminal needed |
| **Full debug log** | `/tmp/cowork_supervisor_v3.log` | Every round | Troubleshooting: `tail -f` |

The status file is **overwritten** each round (always shows current state), while the report file is **appended** (shows history).

## How Detection Works

### Log-based (V2+)
Monitors `~/Library/Logs/Claude/cowork_vm_node.log`:
- `"Spawn succeeded"` → agent is running
- `"Exited, code=0"` → agent stopped → auto-nudge
- `"active=0"` → no active processes → confirmed idle
- `"oom=true"` → out of memory → free memory + retry

### V3 additions
Monitors `~/Library/Logs/Claude/main.log`:
- `503` / `504` status codes → claude.ai service outage
- Process checks via `pgrep` → Desktop/VM crash detection

## Self-Healing Actions (V3)

| Detection | Automatic Action |
|-----------|-----------------|
| Desktop crashed | Restart Claude Desktop (max 5 times) |
| VM died, Desktop alive | Wait 15s → restart Desktop if not recovered |
| Agent idle/exited | GUI nudge via clipboard paste |
| 503 errors > 3 | Notify, pause nudging until recovery |
| OOM kill | Kill Chrome tabs, agent auto-retries |
| Swap > 7GB | Kill largest Chrome tab |
| Swap > 9GB | Kill multiple Chrome tabs |
| Memory < 10% free | Preemptive Chrome tab cleanup |

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

| Machine RAM | Safe Parallel Agents | Swap Warn | Swap Critical |
|-------------|---------------------|-----------|---------------|
| 8GB | 1-2 | 3GB | 5GB |
| 16GB | 2-3 | 7GB | 9GB |
| 32GB+ | 4-5 | 14GB | 18GB |

## Installation

```bash
git clone https://github.com/ChristopherCC-Liu/superchris.git
cp -r superchris ~/.claude/plugins/local/cowork-supervisor

# Install pyautogui if needed
pip install pyautogui
```

## Changelog

### V3 (2026-03-01) — Self-Healing Edition
- Auto-restart Claude Desktop and Cowork VM on crash
- 503/504 service outage detection and smart pause
- OOM kill detection and memory auto-relief
- Swap threshold auto-relief (kill Chrome tabs)
- Memory pressure monitoring with preemptive cleanup
- macOS Notification Center alerts with sound
- **Continuous reporting**: real-time status file + periodic report file + notifications
- PID file for clean process management
- Summary report on exit

### V2 (2026-02-28) — Log-Based Detection
- Switched from screenshot comparison to log-based detection
- Fixed unreliable screenshot monitoring (clock/cursor causes false negatives)

### V1 (2026-02-27) — Initial Release
- Screenshot-based detection (deprecated)
- Basic nudge functionality

## License

MIT
