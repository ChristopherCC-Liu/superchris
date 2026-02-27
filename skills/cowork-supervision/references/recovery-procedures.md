# Recovery Procedures — Detailed Reference

## 1. Single Agent Recovery

### Diagnosis
```
1. Check TaskList — find the stuck agent's task
2. TaskGet — read full task description and current state
3. Check agent process: ps aux | grep claude | grep -v grep
4. Read agent's last output if available
5. Determine: recoverable (send hint) vs needs restart
```

### Recovery Steps
```
1. TaskGet to capture current task description
2. Record what the agent has completed (read output files)
3. SendMessage shutdown_request to the agent
4. Wait 30 seconds for graceful shutdown
5. If no response → TaskStop to force terminate
6. Re-dispatch via Task tool with enhanced prompt:
   - "Continue the following unfinished work: [original task]"
   - "Already completed: [summary of done work]"
   - "Resume from: [breakpoint description]"
7. TaskUpdate to track the new agent
```

## 2. Global RPC Error Recovery

This happens when process name conflicts occur, usually after an interrupted session.

### Recovery Steps
```
1. Record all in-progress tasks and their progress
2. Save TaskList snapshot to file:
   ~/.claude/tasks/{team}/progress_snapshot.json
3. Notify user: "Please Cmd+Q to restart Claude App"
4. After restart, read the snapshot file
5. Re-create Team if needed
6. Re-dispatch each unfinished task with context from snapshot
```

### Snapshot Format
```json
{
  "timestamp": "ISO-8601",
  "team": "team-name",
  "tasks": [
    {
      "id": "1",
      "subject": "task title",
      "status": "in_progress",
      "owner": "agent-name",
      "progress_summary": "what was done",
      "breakpoint": "where to resume"
    }
  ]
}
```

## 3. Swap Overflow Emergency

### Immediate Actions
```
1. STOP dispatching new agents immediately
2. Check current agents: TaskList
3. If possible, let near-complete agents finish
4. Reduce parallelism: keep only 2 agents max
5. Suggest user close: Chrome tabs, Parallels VMs, other heavy apps
```

### Recovery
```
1. Monitor: sysctl vm.swapusage (check every 30s)
2. When swap < 5GB → safe to resume
3. Resume with reduced parallelism (2-3 agents max)
4. Consider using haiku model for less critical tasks to save memory
```

### Prevention
- Pre-flight check swap before starting
- Set hard limit on parallel agents based on available RAM:
  - 8GB RAM → 1-2 agents
  - 16GB RAM → 2-3 agents
  - 32GB+ RAM → 4-5 agents
- Monitor resource pressure every monitoring cycle

## 4. Agent Stuck in Loop

### Detection
- Agent produces similar output repeatedly
- Task progress percentage not advancing
- Same tool calls appearing in sequence

### Resolution
```
1. SendMessage to agent with specific guidance:
   "You appear to be stuck in a loop. Please try a different approach:
    [specific suggestion based on what they're looping on]"
2. If still looping after 2 messages → restart with modified prompt
3. In new prompt, explicitly note: "Previous attempt got stuck on [X].
   Try [alternative approach] instead."
```
