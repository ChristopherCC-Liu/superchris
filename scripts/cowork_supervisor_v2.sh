#!/bin/bash
# Cowork Supervisor V2 - Log-based detection
# Monitors cowork_vm_node.log for agent activity instead of screenshots
# When agent stops, sends nudge via pyautogui + osascript combo

LOG_FILE="/tmp/cowork_supervisor_v2.log"
COWORK_LOG="$HOME/Library/Logs/Claude/cowork_vm_node.log"
MAIN_LOG="$HOME/Library/Logs/Claude/main.log"
CHECK_INTERVAL=60  # Check every 60 seconds
IDLE_THRESHOLD=180  # 3 minutes no log activity = idle
DURATION=$((8 * 3600))  # 8 hours
START_TIME=$(date +%s)
NUDGE_COUNT=0
LAST_NUDGE_TIME=0
NUDGE_COOLDOWN=300  # Don't nudge more than once per 5 minutes

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_cowork_last_activity() {
    # Check the last modification time of cowork log
    if [ -f "$COWORK_LOG" ]; then
        stat -f %m "$COWORK_LOG"
    else
        echo "0"
    fi
}

check_active_processes() {
    # Check if there are active cowork VM processes (remaining active > 0)
    local last_status=$(grep -E "active=" "$COWORK_LOG" 2>/dev/null | tail -1)
    if echo "$last_status" | grep -q "active=0"; then
        echo "idle"
    else
        echo "active"
    fi
}

check_last_exit() {
    # Check if the last event was an exit (agent stopped)
    local last_event=$(tail -5 "$COWORK_LOG" 2>/dev/null | grep -E "Exited|Spawn succeeded|kill called" | tail -1)
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
    sysctl vm.swapusage | awk '{gsub(/M/,""); print $7}'
}

send_nudge() {
    local now=$(date +%s)
    local since_last=$(( now - LAST_NUDGE_TIME ))

    if [ $since_last -lt $NUDGE_COOLDOWN ]; then
        log "SKIP: Nudge cooldown (${since_last}s < ${NUDGE_COOLDOWN}s)"
        return
    fi

    NUDGE_COUNT=$((NUDGE_COUNT + 1))
    LAST_NUDGE_TIME=$now

    # Rotate through different nudge messages
    local msg_num=$(( NUDGE_COUNT % 3 ))
    local msg
    case $msg_num in
        1) msg="Continue working! Start the next uncompleted task from the sidebar. Do not stop or wait for confirmation." ;;
        2) msg="Keep going! Check the task list, find the next task, execute it immediately. Complete all tasks one by one." ;;
        0) msg="Do not stop! You have more tasks to complete. Check the left sidebar and start the next one right now." ;;
    esac

    log "NUDGE #$NUDGE_COUNT: Sending message..."

    # Copy to clipboard
    echo -n "$msg" | pbcopy

    # Use pyautogui to click reply box + osascript to paste and send
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

    # Verify: wait and check if agent started
    sleep 5
    local status=$(check_last_exit)
    if [ "$status" = "running" ]; then
        log "NUDGE SUCCESS: Agent resumed"
    else
        log "NUDGE SENT: Waiting for agent to start (status: $status)"
    fi
}

# ===== Main Loop =====

log "=== Cowork Supervisor V2 Started ==="
log "Detection: cowork_vm_node.log monitoring"
log "Idle threshold: ${IDLE_THRESHOLD}s | Check interval: ${CHECK_INTERVAL}s"
log "Duration: 8 hours | Nudge cooldown: ${NUDGE_COOLDOWN}s"

while true; do
    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [ $ELAPSED -ge $DURATION ]; then
        log "=== 8 hours reached. Supervisor ending. ==="
        break
    fi

    HOURS_LEFT=$(( (DURATION - ELAPSED) / 3600 ))
    MINS_LEFT=$(( ((DURATION - ELAPSED) % 3600) / 60 ))
    SWAP=$(get_swap_mb)

    # Core detection: check log file modification time
    LAST_MOD=$(get_cowork_last_activity)
    NOW=$(date +%s)
    SECONDS_SINCE_ACTIVITY=$(( NOW - LAST_MOD ))

    # Check process status from log
    PROCESS_STATUS=$(check_last_exit)
    ACTIVE_STATUS=$(check_active_processes)

    # Determine if agent is truly idle
    if [ "$ACTIVE_STATUS" = "idle" ] && [ "$PROCESS_STATUS" = "exited" ]; then
        log "!!! IDLE: Agent stopped (last exit ${SECONDS_SINCE_ACTIVITY}s ago) | Swap: ${SWAP}MB | Left: ${HOURS_LEFT}h${MINS_LEFT}m"
        send_nudge
    elif [ $SECONDS_SINCE_ACTIVITY -gt $IDLE_THRESHOLD ] && [ "$PROCESS_STATUS" != "running" ]; then
        log "WARN: No log activity for ${SECONDS_SINCE_ACTIVITY}s (status: $PROCESS_STATUS) | Swap: ${SWAP}MB | Left: ${HOURS_LEFT}h${MINS_LEFT}m"
        if [ $SECONDS_SINCE_ACTIVITY -gt $(( IDLE_THRESHOLD * 2 )) ]; then
            log "!!! STALE: Agent likely stopped, sending nudge"
            send_nudge
        fi
    else
        log "OK: Agent active (status: $PROCESS_STATUS, last activity: ${SECONDS_SINCE_ACTIVITY}s ago) | Swap: ${SWAP}MB | Left: ${HOURS_LEFT}h${MINS_LEFT}m"
    fi

    # Swap monitoring
    SWAP_INT=${SWAP%%.*}
    if [ "${SWAP_INT:-0}" -gt 8000 ]; then
        log "!!! SWAP CRITICAL: ${SWAP}MB > 8GB"
    fi

    # Check if Claude app is alive
    if ! pgrep -f "Claude.app/Contents/MacOS/Claude" > /dev/null; then
        log "!!! CLAUDE CRASHED: Attempting restart"
        open -a Claude
        sleep 15
    fi

    sleep $CHECK_INTERVAL
done

log "=== Supervisor V2 Summary ==="
log "Total nudges: $NUDGE_COUNT | Runtime: ${ELAPSED}s"
