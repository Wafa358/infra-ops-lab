#!/usr/bin/env bash
# log-triage.sh - summarise a log file so an incident can be triaged in seconds.
#
# Usage:
#   log-triage.sh [-t auth|nginx|app] [-n TOP] [-b THRESHOLD] FILE...
#
#   -t TYPE        log type; guessed from the file name when omitted
#                  auth  : sshd lines from /var/log/auth.log (failed logins per IP)
#                  nginx : access log in "combined" format (status classes, top IPs, 5xx paths)
#                  app   : application log with ERROR/WARN/INFO levels (counts, top errors)
#   -n TOP         how many entries to show in each top list (default: 5)
#   -b THRESHOLD   failed SSH logins from one IP that count as a brute-force suspect (default: 5)
#
# Compressed rotated logs (*.gz) are read directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

TYPE=""
TOP=5
BRUTE=5

while getopts ":t:n:b:h" opt; do
  case "$opt" in
    t) TYPE="$OPTARG" ;;
    n) TOP="$OPTARG" ;;
    b) BRUTE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) usage >&2; die "option -$OPTARG needs a value" 2 ;;
    *) usage >&2; die "unknown option: -$OPTARG" 2 ;;
  esac
done
shift $((OPTIND - 1))

(( $# > 0 )) || { usage >&2; die "give at least one log file" 2; }
[[ "$TOP" =~ ^[0-9]+$ && "$BRUTE" =~ ^[0-9]+$ ]] || die "-n and -b must be numbers" 2

guess_type() {
  case "$(basename -- "$1")" in
    auth.log*|secure*) echo auth ;;
    *access*)          echo nginx ;;
    *)                 echo app ;;
  esac
}

triage_auth() {
  local data="$1"
  echo "== SSH authentication =="
  printf 'failed password attempts: %s\n' "$(grep -c 'Failed password' <<<"$data" || true)"
  printf 'invalid user attempts:    %s\n' "$(grep -c 'Invalid user' <<<"$data" || true)"
  printf 'accepted logins:          %s\n' "$(grep -c 'Accepted ' <<<"$data" || true)"
  echo
  echo "-- top source IPs of failed logins --"
  grep 'Failed password' <<<"$data" \
    | sed -E 's/.* from ([0-9a-fA-F.:]+) port.*/\1/' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk -v t="$BRUTE" '{ flag = ($1 >= t) ? "  <- possible brute force" : ""; printf "%6d %s%s\n", $1, $2, flag }'
}

triage_nginx() {
  local data="$1"
  echo "== HTTP access log =="
  echo "-- requests by status class --"
  # combined format: the status code is the 9th whitespace-separated field
  awk '$9 ~ /^[1-5][0-9][0-9]$/ { c[substr($9, 1, 1) "xx"]++ } END { for (k in c) printf "%s %d\n", k, c[k] }' <<<"$data" | sort
  echo
  echo "-- top client IPs --"
  awk '{ print $1 }' <<<"$data" | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{ printf "%6d %s\n", $1, $2 }'
  echo
  echo "-- paths returning 5xx --"
  awk '$9 ~ /^5/ { print $7 }' <<<"$data" | sort | uniq -c | sort -rn | head -n "$TOP" | awk '{ printf "%6d %s\n", $1, $2 }'
}

triage_app() {
  local data="$1" level
  echo "== Application log =="
  for level in ERROR WARN INFO; do
    printf '%-5s %s\n' "$level" "$(grep -cw "$level" <<<"$data" || true)"
  done
  echo
  echo "-- most frequent errors --"
  # drop everything up to the level keyword so identical messages group together
  grep -w 'ERROR' <<<"$data" \
    | sed -E 's/.*ERROR[]:)]*[[:space:]]*//' \
    | sort | uniq -c | sort -rn | head -n "$TOP" \
    | awk '{ n = $1; $1 = ""; printf "%6d%s\n", n, $0 }'
}

for file in "$@"; do
  data="$(read_log "$file")"
  type="${TYPE:-$(guess_type "$file")}"
  echo "### $file ($type)"
  case "$type" in
    auth)  triage_auth "$data" ;;
    nginx) triage_nginx "$data" ;;
    app)   triage_app "$data" ;;
    *)     die "unknown log type: $type (use auth, nginx or app)" 2 ;;
  esac
  echo
done
