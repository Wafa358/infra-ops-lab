#!/usr/bin/env bash
# restore.sh - verify a backup's checksum, then restore it.
#
# Usage:
#   restore.sh -a ARCHIVE -t TARGET_DIR [-f]
#
#   -a ARCHIVE     a .tar.gz written by backup.sh (its .sha256 must sit next to it)
#   -t TARGET_DIR  directory to extract into (created if missing)
#   -f             allow restoring into a non-empty target directory
#
# The restore stops before touching anything if the checksum does not match.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

ARCHIVE=""
TARGET=""
FORCE=0

while getopts ":a:t:fh" opt; do
  case "$opt" in
    a) ARCHIVE="$OPTARG" ;;
    t) TARGET="$OPTARG" ;;
    f) FORCE=1 ;;
    h) usage; exit 0 ;;
    :) usage >&2; die "option -$OPTARG needs a value" 2 ;;
    *) usage >&2; die "unknown option: -$OPTARG" 2 ;;
  esac
done

[[ -n "$ARCHIVE" && -n "$TARGET" ]] || { usage >&2; die "-a and -t are required" 2; }
[[ -f "$ARCHIVE" ]] || die "archive not found: $ARCHIVE" 2
[[ -f "$ARCHIVE.sha256" ]] || die "checksum file missing: $ARCHIVE.sha256" 2
require_cmd tar sha256sum

dir="$(cd "$(dirname -- "$ARCHIVE")" && pwd)"
if ! ( cd "$dir" && sha256sum --quiet -c -- "$(basename -- "$ARCHIVE").sha256" ) >/dev/null 2>&1; then
  die "checksum mismatch for $ARCHIVE - refusing to restore" 1
fi
info "checksum OK for $(basename -- "$ARCHIVE")"

mkdir -p -- "$TARGET"
if [[ -n "$(ls -A -- "$TARGET")" && "$FORCE" -ne 1 ]]; then
  die "target $TARGET is not empty (use -f to restore anyway)" 2
fi

tar -C "$TARGET" -xzf "$ARCHIVE"
info "restored into $TARGET"
