#!/usr/bin/env bats
# Tests for scripts/backup.sh and scripts/restore.sh: a full round trip,
# rotation, and refusal to restore a corrupted archive.

setup() {
  BK="$BATS_TEST_DIRNAME/../scripts/backup.sh"
  RS="$BATS_TEST_DIRNAME/../scripts/restore.sh"
  SRC="$BATS_TEST_TMPDIR/appdata"
  DEST="$BATS_TEST_TMPDIR/backups"
  mkdir -p "$SRC/conf"
  echo "port=8000" > "$SRC/conf/app.conf"
  echo "hello" > "$SRC/data.txt"
}

@test "backup writes an archive and a matching checksum" {
  BACKUP_TS=20261117T100000Z run "$BK" -s "$SRC" -d "$DEST"
  [ "$status" -eq 0 ]
  [ -f "$DEST/appdata-20261117T100000Z.tar.gz" ]
  [ -f "$DEST/appdata-20261117T100000Z.tar.gz.sha256" ]
  (cd "$DEST" && sha256sum -c appdata-20261117T100000Z.tar.gz.sha256)
}

@test "rotation keeps only the newest KEEP archives" {
  for ts in 20261117T100000Z 20261117T110000Z 20261117T120000Z 20261117T130000Z; do
    BACKUP_TS=$ts "$BK" -s "$SRC" -d "$DEST" -k 2 2>/dev/null
  done
  run ls "$DEST"
  [[ "$output" != *"T100000Z"* ]]
  [[ "$output" != *"T110000Z"* ]]
  [[ "$output" == *"appdata-20261117T120000Z.tar.gz"* ]]
  [[ "$output" == *"appdata-20261117T130000Z.tar.gz"* ]]
}

@test "restore round trip gives back identical files" {
  archive="$(BACKUP_TS=20261117T100000Z "$BK" -s "$SRC" -d "$DEST" 2>/dev/null)"
  run "$RS" -a "$archive" -t "$BATS_TEST_TMPDIR/restored"
  [ "$status" -eq 0 ]
  diff -r "$SRC" "$BATS_TEST_TMPDIR/restored/appdata"
}

@test "restore refuses a corrupted archive" {
  archive="$(BACKUP_TS=20261117T100000Z "$BK" -s "$SRC" -d "$DEST" 2>/dev/null)"
  echo "corruption" >> "$archive"
  run "$RS" -a "$archive" -t "$BATS_TEST_TMPDIR/restored"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -d "$BATS_TEST_TMPDIR/restored/appdata" ]
}

@test "restore refuses a non-empty target unless -f is given" {
  archive="$(BACKUP_TS=20261117T100000Z "$BK" -s "$SRC" -d "$DEST" 2>/dev/null)"
  mkdir -p "$BATS_TEST_TMPDIR/busy" && touch "$BATS_TEST_TMPDIR/busy/existing"
  run "$RS" -a "$archive" -t "$BATS_TEST_TMPDIR/busy"
  [ "$status" -eq 2 ]
  run "$RS" -a "$archive" -t "$BATS_TEST_TMPDIR/busy" -f
  [ "$status" -eq 0 ]
}

@test "backup of a missing source fails" {
  run "$BK" -s "$BATS_TEST_TMPDIR/missing" -d "$DEST"
  [ "$status" -eq 2 ]
}
