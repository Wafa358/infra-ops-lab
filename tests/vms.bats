#!/usr/bin/env bats
# vms/vms.sh inventory, run against a fake multipass (tests/fixtures/bin/multipass).

bats_require_minimum_version 1.5.0

setup() {
  FIX="$BATS_TEST_DIRNAME/fixtures"
  export MULTIPASS="$FIX/bin/multipass"
  export LAB_INVENTORY="$BATS_TEST_TMPDIR/inventory.ini"
  export LAB_KNOWN_HOSTS="$BATS_TEST_TMPDIR/known_hosts"
  VMS="$BATS_TEST_DIRNAME/../vms/vms.sh"
}

# known_host IP : add a host key for IP to the lab known_hosts file.
known_host() {
  [[ -f "$BATS_TEST_TMPDIR/hostkey.pub" ]] || ssh-keygen -q -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/hostkey"
  echo "$1 $(cut -d' ' -f1-2 "$BATS_TEST_TMPDIR/hostkey.pub")" >> "$LAB_KNOWN_HOSTS"
}

known() { ssh-keygen -F "$1" -f "$LAB_KNOWN_HOSTS" >/dev/null; }

@test "inventory groups the VMs by name and keeps the first address" {
  FAKE_MP_LIST="$FIX/mp_list_before.json" run "$VMS" inventory
  [ "$status" -eq 0 ]
  grep -qx 'web1 ansible_host=10.97.0.141' "$LAB_INVENTORY"
  grep -qx 'web2 ansible_host=10.97.0.187' "$LAB_INVENTORY"
  grep -qx 'db1 ansible_host=10.97.0.87' "$LAB_INVENTORY"
  [ "$(grep -c ansible_host= "$LAB_INVENTORY")" -eq 5 ]
  [ "$(sed -n '/^\[lab:children\]/,$p' "$LAB_INVENTORY" | tail -n +2 | tr '\n' ' ')" = "web lb db mon " ]
}

@test "a VM without an address is left out with a warning" {
  FAKE_MP_LIST="$FIX/mp_list_after.json" run "$VMS" inventory
  [ "$status" -eq 0 ]
  [[ "$output" == *"db1 has no IPv4 address"* ]]
  run ! grep -q '^db1 ' "$LAB_INVENTORY"
  run ! grep -qx '\[db\]' "$LAB_INVENTORY"
}

@test "addresses that moved to another VM lose their old host key, the others keep it" {
  FAKE_MP_LIST="$FIX/mp_list_before.json" "$VMS" inventory
  for ip in 10.97.0.141 10.97.0.187 10.97.0.38 10.97.0.41; do known_host "$ip"; done
  FAKE_MP_LIST="$FIX/mp_list_after.json" run "$VMS" inventory
  [ "$status" -eq 0 ]
  run ! known 10.97.0.141
  run ! known 10.97.0.187
  known 10.97.0.38
  known 10.97.0.41
  grep -qx 'web1 ansible_host=10.97.0.187' "$LAB_INVENTORY"
}

@test "a first inventory forgets any key stored for the addresses it writes" {
  known_host 10.97.0.38
  FAKE_MP_LIST="$FIX/mp_list_before.json" run "$VMS" inventory
  [ "$status" -eq 0 ]
  run ! known 10.97.0.38
}

@test "inventory stops with a clear message when Multipass does not answer" {
  FAKE_MP_LIST="$BATS_TEST_TMPDIR/missing.json" run "$VMS" inventory
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not list the VMs"* ]]
  [ ! -f "$LAB_INVENTORY" ]
}
