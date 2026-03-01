#!/bin/bash
# Cowork Supervisor V3 - Self-Healing Edition
# V2: Log-based detection + GUI nudge
# V3: + Auto-restart Desktop/VM + Swap auto-relief + 503 detection + macOS notifications
#
# Usage:
#   bash cowork_supervisor_v3.sh &
#   tail -f /tmp/cowork_supervisor_v3.log
#   kill $(cat /tmp/cowork_supervisor_v3.pid)

LOG_FILE="/tmp/cowork_supervisor_v3.log"
PID_FILE="/tmp/cowork_supervisor_v3.pid"
STATUS_FILE="/tmp/cowork_status.txt"       # Real-time status (overwritten each round)
REPORT_FILE="/tmp/cowork_report.txt"       # Periodic report (appended)
COWORK_LOG="$HOME/Library/Logs/Claude/cowork_vm_node.log"
MAIN_LOG="$HOME/Library/Logs/Claude/main.log"
CHECK_INTERVAL=75   # seconds between checks
IDLE_THRESHOLD=180  # 3 min no log activity = idle
DURATION=$((8 * 3600))  # 8 hours max
REPORT_INTERVAL=5        # Send notification report every N rounds
START_TIME=$(date +%s)
NUDGE_COUNT=0
RESTART_COUNT=0
CHROME_KILL_COUNT=0
ALERT_COUNT=0
LAST_NUDGE_TIME=0
NUDGE_COOLDOWN=300       # 5 min between nudges
MAX_RESTARTS=5           # max Desktop restarts before giving up
SWAP_WARN_THRESHOLD=7000 # MB
SWAP_CRIT_THRESHOLD=9000 # MB

echo $$ > "$PID_FILE"

# ===== Utility Functions =====

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1" msg="$2" sound="${3:-Submarine}"
    osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\"" 2>/dev/null
}

# Write real-time status file (overwritten each round, always reflects current state)
write_status() {
    local status_icon="$1"
    local hours_left="$2"
    local mins_left="$3"
    cat > "$STATUS_FILE" << STAT
== Cowork Supervisor V3 Status ==
Updated: $(date '+%Y-%m-%d %H:%M:%S')
Round:   #${ROUND} | Uptime: $(( ($(date +%s) - START_TIME) / 60 ))min | Left: ${hours_left}h${mins_left}m

[${status_icon}] Desktop: PID ${CLAUDE_PID:-DEAD}
[${status_icon}] VM:      PID ${VM_PID_NOW:-DEAD}
[${status_icon}] Agent:   ${PROCESS_STATUS} (${ACTIVE_STATUS}, last log ${SECONDS_SINCE}s ago)

Resources:
  Swap:   ${SWAP}M $([ "${SWAP_INT:-0}" -gt "$SWAP_WARN_THRESHOLD" ] && echo "⚠" || echo "OK")
  Memory: ${MEM_FREE}% free $([ "${MEM_INT:-100}" -lt 10 ] && echo "⚠" || echo "OK")
  503:    ${RECENT_503} recent errors

Actions taken:
  Nudges:   ${NUDGE_COUNT}
  Restarts: ${RESTART_COUNT}/${MAX_RESTARTS}
  Chrome killed: ${CHROME_KILL_COUNT}
  Alerts:   ${ALERT_COUNT}
STAT
}

# Append periodic report (human-readable summary, appended every REPORT_INTERVAL rounds)
write_report() {
    local ts=$(date '+%H:%M:%S')
    local swap_status="OK"
    [ "${SWAP_INT:-0}" -gt "$SWAP_CRIT_THRESHOLD" ] && swap_status="CRITICAL"
    [ "${SWAP_INT:-0}" -gt "$SWAP_WARN_THRESHOLD" ] && [ "${SWAP_INT:-0}" -le "$SWAP_CRIT_THRESHOLD" ] && swap_status="WARN"

    local agent_status="Working"
    [ "$ACTIVE_STATUS" = "idle" ] && agent_status="Idle"
    [ "$PROCESS_STATUS" = "exited" ] && agent_status="Stopped"
    [ "$RECENT_503" -gt 3 ] && agent_status="Service Down"

    cat >> "$REPORT_FILE" << RPT
[$ts] #${ROUND} | Agent: ${agent_status} | Swap: ${SWAP}M (${swap_status}) | Mem: ${MEM_FREE}% | Nudge: ${NUDGE_COUNT} | Restart: ${RESTART_COUNT}
RPT

    # Also send as notification
    notify "Supervisor Report #${ROUND}" "Agent:${agent_status} Swap:${SWAP}M Mem:${MEM_FREE}% Nudge:${NUDGE_COUNT}" "Glass"
}

# ===== Detection Functions =====

get_cowork_last_activity() {
    if [ -f "$COWORK_LOG" ]; then
        stat -f %m "$COWORK_LOG"
    else
        echo "0"
    fi
}

check_active_processes() {
    local last_status=$(grep -E "active=" "$COWORK_LOG" 2>/dev/null | tail -1)
    if echo "$last_status" | grep -q "active=0"; then
        echo "idle"
    else
        echo "active"
    fi
}

check_last_exit() {
    local last_event=$(tail -10 "$COWORK_LOG" 2>/dev/null | grep -E "Exited|Spawn succeeded|kill called" | tail -1)
    if echo "$last_event" | grep -q "Exited"; then
        echo "exited"
    elif echo "$last_event" | grep -q "Spawn succeeded"; then
        echo "running"
    elif echo "$last_event" | grep -q "kill called"; then
        echo "killing"
    else
        echo "unknown"
    fi
}

get_swap_mb() {
    sysctl vm.swapusage 2>/dev/null | awk -F'used = ' '{print $2}' | awk '{printf "%.0f", $1}'
}

get_mem_free_pct() {
    memory_pressure 2>/dev/null | grep "free percentage" | awk '{print $NF}' | tr -d '%'
}

check_503_errors() {
    tail -30 "$MAIN_LOG" 2>/dev/null | grep -c "503"
}

check_vm_alive() {
    pgrep -f "com.apple.Virtualization.VirtualMachine" >/dev/null 2>&1
}

check_desktop_alive() {
    pgrep -f "Claude.app/Contents/MacOS/Claude" >/dev/null 2>&1
}

check_last_oom() {
    tail -20 "$COWORK_LOG" 2>/dev/null | grep -q "oom=true"
}

# ===== Action Functions =====

restart_claude_desktop() {
    RESTART_COUNT=$((RESTART_COUNT + 1))
    if [ "$RESTART_COUNT" -gt "$MAX_RESTARTS" ]; then
        log "[FATAL] Restart limit reached ($MAX_RESTARTS). Stopping auto-restart."
        notify "Supervisor FATAL" "重启次数超限 ($MAX_RESTARTS)，请手动检查" "Basso"
        return 1
    fi

    log "[ACTION] Restarting Claude Desktop (attempt $RESTART_COUNT/$MAX_RESTARTS)..."
    notify "Supervisor" "正在重启 Claude Desktop (第 ${RESTART_COUNT} 次)..."

    # Graceful quit first
    osascript -e 'tell application "Claude" to quit' 2>/dev/null
    sleep 5

    # Force kill if still alive
    if check_desktop_alive; then
        pkill -9 -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null
        sleep 3
    fi

    # Reopen
    open -a "Claude"
    sleep 20  # Wait for Desktop + VM boot

    if check_desktop_alive; then
        log "[ACTION] Claude Desktop restarted successfully"
        notify "Supervisor" "Claude Desktop 重启成功" "Glass"

        # Wait for VM to be ready
        local vm_wait=0
        while ! check_vm_alive && [ $vm_wait -lt 30 ]; do
            sleep 2
            vm_wait=$((vm_wait + 2))
        done

        if check_vm_alive; then
            log "[ACTION] Cowork VM is up after restart"
        else
            log "[WARN] VM not detected after restart, may need manual intervention"
        fi
        return 0
    else
        log "[ACTION] Claude Desktop restart FAILED"
        notify "Supervisor" "Claude Desktop 重启失败！" "Basso"
        return 1
    fi
}

kill_largest_chrome_tab() {
    local biggest=$(ps aux | grep "Chrome Helper (Renderer)" | grep -v grep | sort -k6 -rn | head -1 | awk '{print $2}')
    if [ -n "$biggest" ]; then
        local mem_kb=$(ps -p "$biggest" -o rss= 2>/dev/null)
        local mem_mb=$(( ${mem_kb:-0} / 1024 ))
        kill "$biggest" 2>/dev/null
        CHROME_KILL_COUNT=$((CHROME_KILL_COUNT + 1))
        log "[ACTION] Killed Chrome tab PID:$biggest (${mem_mb}MB) to free memory"
        notify "Supervisor" "关闭 Chrome 标签释放 ${mem_mb}MB 内存"
        return 0
    fi
    return 1
}

send_nudge() {
    local now=$(date +%s)
    local since_last=$(( now - LAST_NUDGE_TIME ))

    if [ $since_last -lt $NUDGE_COOLDOWN ]; then
        log "[SKIP] Nudge cooldown (${since_last}s < ${NUDGE_COOLDOWN}s)"
        return
    fi

    NUDGE_COUNT=$((NUDGE_COUNT + 1))
    LAST_NUDGE_TIME=$now

    # Rotate nudge messages
    local msg_num=$(( NUDGE_COUNT % 3 ))
    local msg
    case $msg_num in
        1) msg="Continue working! Start the next uncompleted task from the sidebar. Do not stop or wait for confirmation." ;;
        2) msg="Keep going! Check the task list, find the next task, execute it immediately. Complete all tasks one by one." ;;
        0) msg="Do not stop! You have more tasks to complete. Check the left sidebar and start the next one right now." ;;
    esac

    log "[NUDGE #$NUDGE_COUNT] Sending: ${msg:0:50}..."

    # Copy to clipboard
    echo -n "$msg" | pbcopy

    # Click reply box via pyautogui (Electron WebView needs this)
    /opt/anaconda3/bin/python3 -c "
import pyautogui, subprocess, time
subprocess.run(['osascript', '-e', 'tell application \"Claude\" to activate'])
time.sleep(0.8)
pyautogui.click(200, 1032)
time.sleep(0.3)
" 2>/dev/null

    # Paste and send via osascript
    osascript -e '
tell application "System Events"
    keystroke "a" using command down
    delay 0.1
    key code 51
    delay 0.2
    keystroke "v" using command down
    delay 0.5
    key code 36
    delay 1
end tell
' 2>/dev/null

    # Verify
    sleep 5
    local status=$(check_last_exit)
    if [ "$status" = "running" ]; then
        log "[NUDGE] Success: Agent resumed"
        notify "Supervisor" "催促成功，Agent 已恢复工作" "Glass"
    else
        log "[NUDGE] Sent, waiting for response (status: $status)"
    fi
}

# ===== Main =====

log "============================================"
log "Cowork Self-Healing Supervisor V3 Started"
log "============================================"
log "PID: $$ | Check: ${CHECK_INTERVAL}s | Idle: ${IDLE_THRESHOLD}s | Duration: 8h"
log "Swap thresholds: warn=${SWAP_WARN_THRESHOLD}MB crit=${SWAP_CRIT_THRESHOLD}MB"
log "Max restarts: $MAX_RESTARTS | Nudge cooldown: ${NUDGE_COOLDOWN}s"
log "Report interval: every ${REPORT_INTERVAL} rounds (~$((CHECK_INTERVAL * REPORT_INTERVAL / 60))min)"
log "Status file: $STATUS_FILE (real-time, use: cat $STATUS_FILE)"
log "Report file: $REPORT_FILE (periodic, use: tail -f $REPORT_FILE)"
: > "$REPORT_FILE"  # Clear report file on start
notify "Supervisor V3" "监控已启动，持续 8 小时" "Glass"

ROUND=0

while true; do
    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [ $ELAPSED -ge $DURATION ]; then
        log "=== 8 hours reached. Supervisor ending. ==="
        notify "Supervisor" "8 小时监控结束" "Glass"
        break
    fi

    ROUND=$((ROUND + 1))
    HOURS_LEFT=$(( (DURATION - ELAPSED) / 3600 ))
    MINS_LEFT=$(( ((DURATION - ELAPSED) % 3600) / 60 ))

    # ---- Collect metrics ----
    SWAP=$(get_swap_mb)
    SWAP_INT=${SWAP%%.*}
    MEM_FREE=$(get_mem_free_pct)
    MEM_INT=${MEM_FREE%%.*}
    RECENT_503=$(check_503_errors)
    LAST_MOD=$(get_cowork_last_activity)
    NOW=$(date +%s)
    SECONDS_SINCE=$(( NOW - LAST_MOD ))
    PROCESS_STATUS=$(check_last_exit)
    ACTIVE_STATUS=$(check_active_processes)
    VM_PID_NOW=$(pgrep -f "com.apple.Virtualization.VirtualMachine" 2>/dev/null)
    CLAUDE_PID=$(pgrep -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null | head -1)

    # ---- Status line ----
    log "[#$ROUND] Process:${PROCESS_STATUS} Active:${ACTIVE_STATUS} LastLog:${SECONDS_SINCE}s Swap:${SWAP}M Mem:${MEM_FREE}% 503:${RECENT_503} Left:${HOURS_LEFT}h${MINS_LEFT}m"

    # ---- Write real-time status file ----
    status_icon="OK"
    [ -z "$CLAUDE_PID" ] && status_icon="!!"
    [ -z "$VM_PID_NOW" ] && status_icon="!!"
    [ "$RECENT_503" -gt 3 ] && status_icon="!!"
    write_status "$status_icon" "$HOURS_LEFT" "$MINS_LEFT"

    # ---- Periodic report (every REPORT_INTERVAL rounds) ----
    if [ $((ROUND % REPORT_INTERVAL)) -eq 0 ]; then
        write_report
    fi

    # ===== Self-Healing Logic =====

    # CASE 1: Claude Desktop crashed → auto-restart
    if ! check_desktop_alive; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        log "[DETECT] Claude Desktop process NOT FOUND"
        restart_claude_desktop
        sleep 15
        continue
    fi

    # CASE 2: VM died but Desktop alive → wait then restart
    if ! check_vm_alive; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        log "[DETECT] Cowork VM NOT FOUND (Desktop alive)"
        sleep 15
        if ! check_vm_alive; then
            log "[DETECT] VM still missing after 15s wait, restarting Desktop"
            restart_claude_desktop
        else
            log "[RECOVER] VM came back on its own"
        fi
        continue
    fi

    # CASE 3: OOM kill detected → reduce load then restart
    if check_last_oom; then
        log "[DETECT] OOM kill detected in cowork log!"
        notify "Supervisor" "Agent 被 OOM 杀掉！正在释放内存..." "Basso"
        kill_largest_chrome_tab
        sleep 2
        kill_largest_chrome_tab
        sleep 10
        # Agent should be re-dispatched by Cowork automatically
    fi

    # CASE 4: Persistent 503 errors → service-side, just log and notify
    if [ "$RECENT_503" -gt 3 ]; then
        ALERT_COUNT=$((ALERT_COUNT + 1))
        log "[DETECT] ${RECENT_503} x 503 errors — claude.ai service issue"
        notify "Supervisor" "claude.ai 503 错误 x${RECENT_503}，等待恢复..." "Basso"
        # Can't self-heal server issues, but don't nudge during outage
        sleep $CHECK_INTERVAL
        continue
    fi

    # CASE 5: Swap critical → emergency memory relief
    if [ "${SWAP_INT:-0}" -gt "$SWAP_CRIT_THRESHOLD" ]; then
        log "[EMERGENCY] Swap ${SWAP}M > ${SWAP_CRIT_THRESHOLD}M!"
        notify "Supervisor EMERGENCY" "Swap ${SWAP}M 即将爆满！正在释放内存" "Basso"
        kill_largest_chrome_tab
        sleep 2
        kill_largest_chrome_tab
        sleep 2
        kill_largest_chrome_tab
    elif [ "${SWAP_INT:-0}" -gt "$SWAP_WARN_THRESHOLD" ]; then
        log "[WARN] Swap ${SWAP}M > ${SWAP_WARN_THRESHOLD}M"
        notify "Supervisor" "Swap 偏高: ${SWAP}M" "Submarine"
        kill_largest_chrome_tab
    fi

    # CASE 6: Memory free < 10% → preemptive relief
    if [ "${MEM_INT:-100}" -lt 10 ]; then
        log "[WARN] Memory free ${MEM_FREE}% < 10%"
        notify "Supervisor" "内存紧张: 仅剩 ${MEM_FREE}% 可用"
        kill_largest_chrome_tab
    fi

    # CASE 7: Agent idle → nudge to continue
    if [ "$ACTIVE_STATUS" = "idle" ] && [ "$PROCESS_STATUS" = "exited" ]; then
        log "[DETECT] Agent IDLE (exited ${SECONDS_SINCE}s ago)"
        send_nudge
    elif [ $SECONDS_SINCE -gt $IDLE_THRESHOLD ] && [ "$PROCESS_STATUS" != "running" ]; then
        log "[WARN] No log activity for ${SECONDS_SINCE}s (status: $PROCESS_STATUS)"
        if [ $SECONDS_SINCE -gt $(( IDLE_THRESHOLD * 2 )) ]; then
            log "[DETECT] Agent likely STALE (${SECONDS_SINCE}s), sending nudge"
            send_nudge
        fi
    fi

    # (Periodic reporting is handled by write_report above every REPORT_INTERVAL rounds)

    sleep $CHECK_INTERVAL
done

# ===== Summary =====
log "============================================"
log "Cowork Supervisor V3 Summary"
log "============================================"
log "Runtime: ${ELAPSED}s (~$((ELAPSED/3600))h)"
log "Rounds: $ROUND"
log "Nudges sent: $NUDGE_COUNT"
log "Desktop restarts: $RESTART_COUNT"
log "Chrome tabs killed: $CHROME_KILL_COUNT"
log "Alerts triggered: $ALERT_COUNT"
log "Status file: $STATUS_FILE"
log "Report file: $REPORT_FILE"
log "============================================"

rm -f "$PID_FILE"
