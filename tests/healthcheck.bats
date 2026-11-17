#!/usr/bin/env bats
# Tests for scripts/healthcheck.sh. Fixtures replace df and /proc/meminfo
# so the results do not depend on the machine running the tests.

setup() {
  HC="$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
  FX="$BATS_TEST_DIRNAME/fixtures"
  export HC_DF_FILE="$FX/df_42.txt"
  export HC_MEMINFO="$FX/meminfo_40.txt"
}

@test "healthy host reports OK and exits 0" {
  run "$HC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk / 42% used"* ]]
  [[ "$output" == *"memory 40% used"* ]]
  [[ "$output" == *"HEALTH: OK"* ]]
}

@test "disk at 85% is a WARNING with the default 80:90 thresholds" {
  HC_DF_FILE="$FX/df_85.txt" run "$HC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING  disk / 85% used"* ]]
}

@test "disk at 85% becomes CRITICAL with custom thresholds 70:80" {
  HC_DF_FILE="$FX/df_85.txt" run "$HC" -d 70:80
  [ "$status" -eq 2 ]
}

@test "memory at 97% is CRITICAL" {
  HC_MEMINFO="$FX/meminfo_97.txt" run "$HC"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CRITICAL memory 97% used"* ]]
}

@test "an active service is OK and an inactive one is CRITICAL" {
  stub="$BATS_TEST_TMPDIR/systemctl"
  printf '#!/usr/bin/env bash\n[ "$3" = "nginx" ]\n' > "$stub"
  chmod +x "$stub"
  HC_SYSTEMCTL="$stub" run "$HC" -s nginx,redis
  [ "$status" -eq 2 ]
  [[ "$output" == *"OK       service nginx is active"* ]]
  [[ "$output" == *"CRITICAL service redis is NOT active"* ]]
}

@test "a reachable URL is OK" {
  page="$BATS_TEST_TMPDIR/index.html"
  echo hello > "$page"
  run "$HC" -u "file://$page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"answered"* ]]
}

@test "an unreachable URL is CRITICAL" {
  run "$HC" -u "file:///does/not/exist"
  [ "$status" -eq 2 ]
  [[ "$output" == *"did not answer"* ]]
}

@test "malformed thresholds exit 3 (UNKNOWN)" {
  run "$HC" -d 90
  [ "$status" -eq 3 ]
}

@test "thresholds with WARN above CRIT are rejected" {
  run "$HC" -m 95:85
  [ "$status" -eq 3 ]
}
