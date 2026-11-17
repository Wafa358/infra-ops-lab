#!/usr/bin/env bats
# Tests for scripts/log-triage.sh against small sample logs in tests/fixtures.

setup() {
  LT="$BATS_TEST_DIRNAME/../scripts/log-triage.sh"
  FX="$BATS_TEST_DIRNAME/fixtures"
}

@test "auth log: counts failed, invalid and accepted logins" {
  run "$LT" "$FX/auth.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed password attempts: 8"* ]]
  [[ "$output" == *"invalid user attempts:    2"* ]]
  [[ "$output" == *"accepted logins:          1"* ]]
}

@test "auth log: flags the IP above the brute-force threshold only" {
  run "$LT" -b 5 "$FX/auth.log"
  [[ "$output" == *"6 203.0.113.7  <- possible brute force"* ]]
  [[ "$output" == *"2 198.51.100.4"* ]]
  [[ "$output" != *"198.51.100.4  <- possible brute force"* ]]
}

@test "nginx log: groups requests by status class" {
  run "$LT" "$FX/nginx_access.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2xx 2"* ]]
  [[ "$output" == *"3xx 1"* ]]
  [[ "$output" == *"4xx 2"* ]]
  [[ "$output" == *"5xx 2"* ]]
  [[ "$output" == *"2 /api/orders"* ]]
}

@test "app log: counts levels and groups identical errors" {
  run "$LT" -t app "$FX/app.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROR 3"* ]]
  [[ "$output" == *"WARN  1"* ]]
  [[ "$output" == *"2 database connection refused"* ]]
}

@test "reads gzip-compressed rotated logs" {
  gz="$BATS_TEST_TMPDIR/app.log.1.gz"
  gzip -c "$FX/app.log" > "$gz"
  run "$LT" -t app "$gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROR 3"* ]]
}

@test "missing file fails with a clear message" {
  run "$LT" "$BATS_TEST_TMPDIR/nope.log"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read log file"* ]]
}

@test "no file argument is a usage error" {
  run "$LT"
  [ "$status" -eq 2 ]
}
