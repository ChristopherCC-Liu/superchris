---
name: cowork-supervision
description: >
  Use when user discusses multi-agent coordination, Cowork troubleshooting,
  agent recovery, or team monitoring strategies. Provides detailed procedures
  for diagnosing and recovering from common Cowork failures.
version: 1.0.0
---

# Cowork Supervision Skill

## Overview
This skill provides knowledge for supervising Claude Code multi-agent teams (Cowork). It covers monitoring, diagnostics, recovery, and resource management.

## Key Concepts

### Agent Lifecycle
1. **Spawned** → Agent created via Task tool
2. **Working** → "Working on it..." status, DO NOT interrupt
3. **Idle** → Between turns, can receive messages
4. **Stuck** → No output for 5+ minutes, needs intervention
5. **Completed** → Task done, output available

### Resource Thresholds (16GB Mac)
| Metric | Safe | Warning | Critical |
|--------|------|---------|----------|
| Swap | < 5GB | 5-7GB | > 9GB |
| Parallel Agents | 2-3 | 4 | 5+ |
| Memory Pressure | Normal | Warn | Critical |

For machines with more RAM, scale thresholds proportionally.

### Common Failure Modes

| Failure | Symptom | Detection |
|---------|---------|-----------|
| RPC Error | "process with name already running" | stderr, process name conflict |
| Agent Timeout | 600s no response | Check process runtime |
| Swap Overflow | System lag, slow commands | `sysctl vm.swapusage` |
| Agent Loop | Repeating same action | Compare consecutive outputs |
| Network Issue | API call failures | `curl api.anthropic.com` |

## Recovery Quick Reference

**Single agent stuck:** TaskGet → record → shutdown_request → TaskStop → re-dispatch with context

**RPC Error:** Snapshot tasks → user restarts app → restore from snapshot

**Swap overflow:** Pause dispatching → reduce parallelism → wait for recovery → resume

## Best Practices
1. Every agent prompt must be **self-contained** — no external context dependencies
2. Use **Task tool** for dispatching, not shell scripts
3. Write **progress snapshots** every 5 minutes for crash recovery
4. **Never interrupt** a "Working on it..." agent
5. Supervisor is always the **last to leave**
