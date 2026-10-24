#!/usr/bin/env bash
# Run a single before/after trial and retain its raw measurements.
set -euo pipefail
umask 077
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -ge 2 && $# -le 3 ]] || fail 'Usage: run_case.sh <oom|cpu|deadlock> <before|after> [seconds]'
case_name=$1
stage=$2
seconds=${3:-50}
[[ $seconds =~ ^[1-9][0-9]*$ ]] || fail 'Duration must be a positive integer.'
[[ $stage == before || $stage == after ]] || fail 'Stage must be before or after.'
(( EUID != 0 )) || fail 'Run as a non-root user.'
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export AGENT_HOME=${AGENT_HOME:-$HOME/agent-leak-lab}
[[ -r $AGENT_HOME/agent.env ]] || fail 'Run scripts/setup.sh first.'
# shellcheck source=/dev/null
source "$AGENT_HOME/agent.env"
[[ -x $AGENT_BINARY ]] || fail "Missing $AGENT_BINARY"
[[ $AGENT_PORT == 15034 ]] || fail 'AGENT_PORT must be 15034.'
for name in ps awk ss setsid top getconf; do
    command -v "$name" >/dev/null || fail "Missing command: $name"
done
[[ -z $(ss -H -ltn 'sport = :15034') ]] || fail 'Port 15034 is already in use.'

# Keep two other variables unchanged when testing one variable.
export MEMORY_LIMIT=512 CPU_MAX_OCCUPY=40 MULTI_THREAD_ENABLE=false
case "$case_name:$stage" in
    oom:before)      MEMORY_LIMIT=256 ;;
    oom:after)       MEMORY_LIMIT=512 ;;
    cpu:before)      CPU_MAX_OCCUPY=80 ;;
    cpu:after)       CPU_MAX_OCCUPY=40 ;;
    deadlock:before) MULTI_THREAD_ENABLE=true ;;
    deadlock:after)  MULTI_THREAD_ENABLE=false ;;
    *) fail 'Unknown case.' ;;
esac
export MEMORY_LIMIT CPU_MAX_OCCUPY MULTI_THREAD_ENABLE
run_dir="$repo_dir/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$case_name-$stage"
[[ ! -e $run_dir ]] || fail 'Run directory already exists.'
mkdir -p "$run_dir/agent-logs"
# Isolate application-generated log files per trial.
export AGENT_LOG_DIR="$run_dir/agent-logs"
{
    printf 'case=%s\nstage=%s\n' "$case_name" "$stage"
    printf 'MEMORY_LIMIT=%s\nCPU_MAX_OCCUPY=%s\nMULTI_THREAD_ENABLE=%s\n' \
        "$MEMORY_LIMIT" "$CPU_MAX_OCCUPY" "$MULTI_THREAD_ENABLE"
    printf 'started_utc=%s\nmax_observation_seconds=%s\n' "$(date -u +%FT%TZ)" "$seconds"
    printf 'binary_sha256=%s\n' "$(sha256sum "$AGENT_BINARY" | awk '{print $1}')"
} > "$run_dir/settings.txt"

# setsid creates a new group; this lets cleanup target only our trial.
setsid "$AGENT_BINARY" > "$run_dir/application.log" 2>&1 &
leader=$!
monitor_pid=
finished=0

group_alive() {
    ps -eo pgid=,stat= | awk -v g="$leader" \
        '$1==g && $2 !~ /^[ZX]/ {found=1} END {exit !found}'
}
snapshot() {
    {
        printf '\n[%s]\n' "$(date -u +%FT%TZ)"
        ps -eo pid,ppid,pgid,stat,%cpu,%mem,rss,etime,comm | \
            awk -v g="$leader" 'NR==1 || $3==g'
        ps -eLo pid,tid,pgid,stat,wchan:24,time,comm | \
            awk -v g="$leader" 'NR==1 || $3==g'
        ss -H -ltn 'sport = :15034'
    } >> "$run_dir/processes.txt"
}
cleanup() {
    (( finished )) && return
    finished=1
    trap - EXIT INT TERM
    # Snapshot before interference from our explicit cleanup.
    snapshot
    if [[ -n $monitor_pid ]]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
    if group_alive; then
        kill -TERM -- "-$leader" 2>/dev/null || true
        sleep 1
        group_alive && kill -KILL -- "-$leader" 2>/dev/null || true
    fi
    app_exit=0
    wait "$leader" || app_exit=$?
    printf 'reason=%s\nexit_code=%s\nended_utc=%s\n' \
        "$reason" "$app_exit" "$(date -u +%FT%TZ)" > "$run_dir/result.txt"
}
reason=interrupted
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash "$repo_dir/scripts/monitor.sh" "$leader" "$run_dir/monitor.tsv" &
monitor_pid=$!
reason=app_exit
for ((elapsed=0; elapsed<seconds; elapsed++)); do
    group_alive || break
    (( elapsed % 10 == 0 )) && snapshot
    sleep 1
done
if group_alive; then
    reason=observation_limit
fi
cleanup
printf 'Evidence: %s\nReason: %s (exit=%s)\n' "$run_dir" "$reason" "$app_exit"
