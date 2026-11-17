#!/usr/bin/env bash
# healthcheck.sh - check disk, memory, services and an HTTP endpoint on a Linux host.
#
# Exit codes follow the Nagios convention, so the script can feed any monitoring tool:
#   0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN (bad usage or missing data)
#
# Usage:
#   healthcheck.sh [-p PATH] [-d WARN:CRIT] [-m WARN:CRIT] [-s svc1,svc2] [-u URL]
#
#   -p PATH        filesystem to check (default: /)
#   -d WARN:CRIT   disk usage thresholds in percent (default: 80:90)
#   -m WARN:CRIT   memory usage thresholds in percent (default: 85:95)
#   -s SERVICES    comma-separated systemd units that must be active (e.g. nginx,ssh)
#   -u URL         URL that must answer successfully within 5 seconds
#
# Test hooks (used by the bats tests, not needed in normal use):
#   HC_DF_FILE       file containing `df -P` output instead of running df
#   HC_MEMINFO       file to read instead of /proc/meminfo
#   HC_SYSTEMCTL     command to use instead of systemctl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

PATH_TO_CHECK="/"
DISK_T="80:90"
MEM_T="85:95"
SERVICES=""
URL=""

while getopts ":p:d:m:s:u:h" opt; do
  case "$opt" in
    p) PATH_TO_CHECK="$OPTARG" ;;
    d) DISK_T="$OPTARG" ;;
    m) MEM_T="$OPTARG" ;;
    s) SERVICES="$OPTARG" ;;
    u) URL="$OPTARG" ;;
    h) usage; exit "$EXIT_OK" ;;
    :) usage >&2; die "option -$OPTARG needs a value" ;;
    *) usage >&2; die "unknown option: -$OPTARG" ;;
  esac
done

# parse_thresholds "80:90" -> sets WARN and CRIT, validates them.
parse_thresholds() {
  local spec="$1" name="$2"
  [[ "$spec" =~ ^([0-9]{1,3}):([0-9]{1,3})$ ]] || die "$name thresholds must look like WARN:CRIT, got '$spec'"
  WARN="${BASH_REMATCH[1]}"
  CRIT="${BASH_REMATCH[2]}"
  (( WARN <= CRIT && CRIT <= 100 )) || die "$name thresholds need WARN <= CRIT <= 100, got '$spec'"
}

STATUS=$EXIT_OK
# report LEVEL MESSAGE : print one result line and keep the worst level seen.
report() {
  local level="$1" msg="$2" label
  case "$level" in
    "$EXIT_OK") label="OK" ;;
    "$EXIT_WARNING") label="WARNING" ;;
    "$EXIT_CRITICAL") label="CRITICAL" ;;
    *) label="UNKNOWN" ;;
  esac
  printf '%-8s %s\n' "$label" "$msg"
  (( level > STATUS )) && STATUS=$level
  return 0
}

# level_for VALUE : compare VALUE with the current WARN/CRIT thresholds.
level_for() {
  local v="$1"
  if (( v >= CRIT )); then echo "$EXIT_CRITICAL"
  elif (( v >= WARN )); then echo "$EXIT_WARNING"
  else echo "$EXIT_OK"; fi
}

check_disk() {
  parse_thresholds "$DISK_T" "disk"
  local out pct
  if [[ -n "${HC_DF_FILE:-}" ]]; then
    out="$(cat -- "$HC_DF_FILE")"
  else
    out="$(df -P -- "$PATH_TO_CHECK")" || { report "$EXIT_UNKNOWN" "disk: cannot read $PATH_TO_CHECK"; return; }
  fi
  # df -P: the 5th column of the last line is "Use%", e.g. "42%".
  pct="$(awk 'END { gsub("%", "", $5); print $5 }' <<<"$out")"
  [[ "$pct" =~ ^[0-9]+$ ]] || { report "$EXIT_UNKNOWN" "disk: unexpected df output"; return; }
  report "$(level_for "$pct")" "disk $PATH_TO_CHECK ${pct}% used (warn ${WARN}%, crit ${CRIT}%)"
}

check_memory() {
  parse_thresholds "$MEM_T" "memory"
  local file="${HC_MEMINFO:-/proc/meminfo}" total avail pct
  [[ -r "$file" ]] || { report "$EXIT_UNKNOWN" "memory: cannot read $file"; return; }
  total="$(awk '/^MemTotal:/ { print $2 }' "$file")"
  avail="$(awk '/^MemAvailable:/ { print $2 }' "$file")"
  [[ -n "$total" && -n "$avail" && "$total" -gt 0 ]] || { report "$EXIT_UNKNOWN" "memory: MemTotal/MemAvailable missing"; return; }
  pct=$(( (total - avail) * 100 / total ))
  report "$(level_for "$pct")" "memory ${pct}% used (warn ${WARN}%, crit ${CRIT}%)"
}

check_services() {
  [[ -z "$SERVICES" ]] && return 0
  local ctl="${HC_SYSTEMCTL:-systemctl}" svc
  if ! command -v "${ctl%% *}" >/dev/null 2>&1; then
    report "$EXIT_UNKNOWN" "services: systemctl not available"
    return
  fi
  IFS=',' read -r -a svcs <<<"$SERVICES"
  for svc in "${svcs[@]}"; do
    if $ctl is-active --quiet "$svc"; then
      report "$EXIT_OK" "service $svc is active"
    else
      report "$EXIT_CRITICAL" "service $svc is NOT active"
    fi
  done
}

check_url() {
  [[ -z "$URL" ]] && return 0
  require_cmd curl
  if curl -fsS -o /dev/null --max-time 5 -- "$URL" 2>/dev/null; then
    report "$EXIT_OK" "url $URL answered"
  else
    report "$EXIT_CRITICAL" "url $URL did not answer successfully"
  fi
}

check_disk
check_memory
check_services
check_url

case "$STATUS" in
  0) echo "HEALTH: OK" ;;
  1) echo "HEALTH: WARNING" ;;
  2) echo "HEALTH: CRITICAL" ;;
  *) echo "HEALTH: UNKNOWN" ;;
esac
exit "$STATUS"
