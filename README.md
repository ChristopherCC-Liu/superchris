# Cowork Supervisor Plugin

Monitor, manage, and recover multi-agent teams in Claude Code.

## Features

- **Automated monitoring loop** — checks agent health, resource pressure, and task progress every 60-90s
- **Crash recovery** — detects stuck agents and re-dispatches with preserved context
- **Resource protection** — monitors swap/memory pressure, auto-reduces parallelism when needed
- **Progress snapshots** — periodic state saves for recovery after interruptions
- **Status reports** — structured updates on team progress

## Requirements

- Claude Code CLI
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable set

## Usage

### Slash Command
```
/supervisor Build a REST API with tests
```

### Trigger Phrases
The supervisor agent also activates on these phrases:
- "启动 Supervisor"
- "监控 Cowork"
- "开始监工"
- "Start supervisor"
- "Monitor cowork"

### What Happens
1. **Pre-flight check** — verifies system resources and cleans up stale processes
2. **Team creation** — breaks your task into parallel subtasks and spawns agents
3. **Monitoring loop** — continuously checks health, progress, and resources
4. **Exception handling** — automatically recovers from crashes, RPC errors, and resource exhaustion
5. **Final report** — generates summary when all tasks complete, waits for your confirmation

## Resource Guidelines

| Machine RAM | Safe Parallel Agents |
|-------------|---------------------|
| 8GB | 1-2 |
| 16GB | 2-3 |
| 32GB+ | 4-5 |

## Installation

Copy this plugin directory to your Claude Code plugins folder:

```bash
cp -r cowork-supervisor-plugin ~/.claude/plugins/local/cowork-supervisor
```

Or add as a local plugin path in your Claude Code settings.

## License

MIT
