#!/usr/bin/env bash
# backup.sh - compressed, checksummed, rotated backups of a directory.
#
# Usage:
#   backup.sh -s SOURCE_DIR -d DEST_DIR [-k KEEP]
#
#   -s SOURCE_DIR  directory to back up
#   -d DEST_DIR    where archives are stored (created if missing)
#   -k KEEP        how many archives of this source to keep (default: 7)
#
# Each run writes NAME-YYYYmmddTHHMMSSZ.tar.gz plus a .sha256 file next to it,
# then deletes the oldest archives beyond KEEP. The archive path is printed on stdout.
# BACKUP_TS can override the timestamp (used by the tests).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

SRC=""
DEST=""
KEEP=7

while getopts ":s:d:k:h" opt; do
  case "$opt" in
    s) SRC="$OPTARG" ;;
    d) DEST="$OPTARG" ;;
    k) KEEP="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) usage >&2; die "option -$OPTARG needs a value" 2 ;;
    *) usage >&2; die "unknown option: -$OPTARG" 2 ;;
  esac
done

[[ -n "$SRC" && -n "$DEST" ]] || { usage >&2; die "-s and -d are required" 2; }
[[ -d "$SRC" ]] || die "source is not a directory: $SRC" 2
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "-k must be a positive number" 2
require_cmd tar gzip sha256sum

mkdir -p -- "$DEST"
SRC="$(cd "$SRC" && pwd)"
name="$(basename -- "$SRC")"
ts="${BACKUP_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
archive="$DEST/$name-$ts.tar.gz"

[[ -e "$archive" ]] && die "archive already exists: $archive" 2

# Write to a temporary file first so an interrupted run never leaves a half archive.
tmp="$archive.partial"
trap 'rm -f -- "$tmp"' EXIT
tar -C "$(dirname -- "$SRC")" -czf "$tmp" -- "$name"
mv -- "$tmp" "$archive"
( cd "$DEST" && sha256sum -- "$(basename -- "$archive")" > "$(basename -- "$archive").sha256" )
info "created $archive ($(du -h -- "$archive" | cut -f1))"

# Rotation: archive names sort by time, so everything before the last KEEP goes.
mapfile -t all < <(find "$DEST" -maxdepth 1 -name "$name-*.tar.gz" -printf '%f\n' | sort)
excess=$(( ${#all[@]} - KEEP ))
for (( i = 0; i < excess; i++ )); do
  rm -f -- "$DEST/${all[i]}" "$DEST/${all[i]}.sha256"
  info "rotated out ${all[i]}"
done

echo "$archive"
