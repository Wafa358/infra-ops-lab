#!/usr/bin/env bash
# Shared helpers for the infra-ops-lab scripts. Source this file; do not run it.

[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# Nagios-style exit codes, also used as severity levels (used by the scripts that source this file).
# shellcheck disable=SC2034
readonly EXIT_OK=0 EXIT_WARNING=1 EXIT_CRITICAL=2 EXIT_UNKNOWN=3

_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Logs go to stderr so that stdout stays clean for results.
log()  { printf '%s [%s] %s\n' "$(_ts)" "$1" "${*:2}" >&2; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
err()  { log ERROR "$@"; }

# die MESSAGE [EXIT_CODE]
die() {
  err "$1"
  exit "${2:-$EXIT_UNKNOWN}"
}

# require_cmd CMD... : stop early with a clear message if a tool is missing.
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# read_log FILE : print a log file, transparently decompressing .gz files.
read_log() {
  local f="$1"
  [[ -r "$f" ]] || die "cannot read log file: $f"
  case "$f" in
    *.gz) gzip -dc -- "$f" ;;
    *)    cat -- "$f" ;;
  esac
}
