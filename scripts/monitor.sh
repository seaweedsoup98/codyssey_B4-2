#!/usr/bin/env bash
# Sample every live PID in one process group at ~1-second intervals.
set -euo pipefail
[[ $# == 2 && $1 =~ ^[1-9][0-9]*$ ]] || {
    echo 'Usage: monitor.sh <process-group-id> <output.tsv>' >&2; exit 2;
}
pgid=$1
output=$2
hz=$(getconf CLK_TCK)
declare -A previous_ticks previous_time start_ticks
printf 'timestamp_utc\tpid\tstate\trss_mib\tcpu_pct\n' > "$output"

while :; do
    found=0
    while read -r pid; do
        [[ -n $pid ]] || continue
        [[ -r /proc/$pid/stat && -r /proc/$pid/status ]] || continue
        stat_line=$(cat "/proc/$pid/stat" 2>/dev/null) || continue
        # Strip the executable name; /proc fields 3.. begin at index 0.
        read -r -a fields <<< "${stat_line##*) }"
        [[ ${fields[0]} != Z && ${fields[0]} != X ]] || continue
        ticks=$((fields[11] + fields[12]))  # utime + stime, fields 14 and 15
        start=${fields[19]}                 # starttime, field 22 (PID-reuse guard)
        rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null) || continue
        [[ $rss =~ ^[0-9]+$ ]] || continue
        read -r now _ < /proc/uptime
        cpu=NA
        if [[ ${start_ticks[$pid]:-} == "$start" && -n ${previous_time[$pid]:-} ]]; then
            cpu=$(awk -v d="$((ticks - previous_ticks[$pid]))" \
                -v dt="$now" -v prev="${previous_time[$pid]}" -v hz="$hz" \
                'BEGIN {elapsed=dt-prev; if(elapsed>0) printf "%.2f",100*d/hz/elapsed; else print "NA"}')
        fi
        printf '%s\t%s\t%s\t%.2f\t%s\n' "$(date -u +%FT%TZ)" \
            "$pid" "${fields[0]}" "$(awk -v k="$rss" 'BEGIN {print k/1024}')" "$cpu" >> "$output"
        previous_ticks[$pid]=$ticks
        previous_time[$pid]=$now
        start_ticks[$pid]=$start
        found=1
    done < <(ps -eo pid=,pgid=,stat= | awk -v g="$pgid" '$2==g && $3 !~ /^[ZX]/ {print $1}')
    (( found )) || break
    sleep 1
done
