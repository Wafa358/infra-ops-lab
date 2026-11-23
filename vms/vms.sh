#!/usr/bin/env bash
# vms.sh - create, list and delete the lab VMs with Multipass, from WSL.
#
# Usage:
#   vms/vms.sh up          create the lab VMs (existing ones are kept) and write ansible/inventory.ini
#   vms/vms.sh inventory   rewrite ansible/inventory.ini from the running VMs
#   vms/vms.sh list        show the VMs and their addresses
#   vms/vms.sh ssh NAME    open an SSH session on a VM with the lab key
#   vms/vms.sh down        delete the VMs for good (asks first)
#
# Needs Multipass for Windows. If WSL cannot reach the VMs, run vms/fix-wsl-routing.ps1
# in an administrator PowerShell (Windows resets that setting at every reboot).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$REPO_DIR/scripts/lib/common.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

KEY="${LAB_KEY:-$HOME/.ssh/infra_lab}"
# The lab keeps its own known_hosts file (ansible.cfg points SSH at it too), so that the
# churn of VM addresses never touches the entries of the user's other servers.
KNOWN_HOSTS="${LAB_KNOWN_HOSTS:-$HOME/.ssh/infra_lab_known_hosts}"
IMAGE="24.04"
INVENTORY="${LAB_INVENTORY:-$REPO_DIR/ansible/inventory.ini}"
# name:cpus:memory:disk
NODES=("web1:1:1G:8G" "web2:1:1G:8G" "lb1:1:1G:8G" "db1:1:1G:8G" "mon1:1:2G:10G")

find_multipass() {
  local win="/mnt/c/Program Files/Multipass/bin/multipass.exe"
  if [[ -n "${MULTIPASS:-}" ]]; then echo "$MULTIPASS"
  elif command -v multipass.exe >/dev/null 2>&1; then command -v multipass.exe
  elif [[ -x "$win" ]]; then echo "$win"
  elif command -v multipass >/dev/null 2>&1; then command -v multipass
  else die "Multipass not found: install it on Windows with 'winget install -e --id Canonical.Multipass'" 2
  fi
}

MP="$(find_multipass)"
# Windows programs end their lines with CRLF; strip the CR so Bash can parse the output.
mp() { "$MP" "$@" | tr -d '\r'; }

# vm_ips : one "NAME IP" line per VM, IP "-" while it has none. One call for all VMs:
# multipass.exe is slow to start from WSL, and "list" does not log in to the VMs like "info".
vm_ips() {
  mp list --format json | python3 -c '
import json, sys
for vm in json.load(sys.stdin).get("list", []):
    ips = [a for a in vm.get("ipv4") or [] if a and a != "N/A"]
    print(vm["name"], ips[0] if ips else "-")'
}

# ip_of NAME : first IPv4 address of a VM, empty if it has none (yet).
ip_of() { vm_ips | awk -v n="$1" '$1 == n && $2 != "-" { print $2 }'; }

# forget_host_keys IP... : drop the stored host key of these addresses.
forget_host_keys() {
  local ip
  [[ -f "$KNOWN_HOSTS" ]] || return 0
  for ip in "$@"; do
    if ssh-keygen -F "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
      ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1
      info "forgot the old host key of $ip"
    fi
  done
}

ensure_key() {
  if [[ ! -f "$KEY" ]]; then
    info "creating the lab SSH key $KEY"
    mkdir -p -- "$(dirname -- "$KEY")"
    ssh-keygen -q -t ed25519 -N "" -C "infra-ops-lab" -f "$KEY"
  fi
}

cloud_init() {
  sed "s|__PUBKEY__|$(cat -- "$KEY.pub")|" "$SCRIPT_DIR/cloud-init.yaml"
}

cmd_inventory() {
  local spec name ip group list
  local -A ip_now=() ip_before=() members=()
  local -a groups=() changed=()
  list="$(vm_ips)" || die "could not list the VMs - is Multipass running?" 2
  while read -r name ip; do ip_now[$name]="$ip"; done <<<"$list"
  if [[ -f "$INVENTORY" ]]; then
    while read -r name ip; do ip_before[$name]="$ip"; done \
      < <(sed -n 's/^\([a-z0-9-]*\) ansible_host=\([0-9.]*\)$/\1 \2/p' "$INVENTORY")
  fi
  for spec in "${NODES[@]}"; do
    name="${spec%%:*}"
    group="${name%%[0-9]*}"   # web1 -> web
    ip="${ip_now[$name]:--}"
    if [[ "$ip" == "-" ]]; then
      warn "$name has no IPv4 address (is it running?) - left out of the inventory"
      continue
    fi
    [[ "${ip_before[$name]:-}" == "$ip" ]] || changed+=("$ip")
    [[ -n "${members[$group]+set}" ]] || groups+=("$group")
    members[$group]+="$name ansible_host=$ip"$'\n'
  done
  # After a reboot Hyper-V can hand the addresses out again in another order. An address
  # that now belongs to another VM would fail SSH's host key check, so forget the keys of
  # the addresses that changed; SSH stores the new key on the next connection (accept-new).
  # Addresses that kept their VM keep their key, and a changed key there is still refused.
  forget_host_keys "${changed[@]}"
  {
    echo "# Written by vms/vms.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ) - do not edit, run 'make inventory'."
    for group in "${groups[@]}"; do
      printf '[%s]\n%s\n' "$group" "${members[$group]}"
    done
    printf '[lab:children]\n'
    printf '%s\n' "${groups[@]}"
  } > "$INVENTORY"
  info "wrote $INVENTORY"
  cat -- "$INVENTORY"
}

cmd_up() {
  local spec name cpus mem disk existing
  ensure_key
  existing="$(vm_ips | awk '{ print $1 }')" || die "could not list the VMs - is Multipass running?" 2
  for spec in "${NODES[@]}"; do
    IFS=: read -r name cpus mem disk <<<"$spec"
    if grep -qx -- "$name" <<<"$existing"; then
      info "$name already exists - keeping it"
      continue
    fi
    info "launching $name (cpus=$cpus memory=$mem disk=$disk)"
    cloud_init | "$MP" launch "$IMAGE" --name "$name" --cpus "$cpus" --memory "$mem" --disk "$disk" --cloud-init -
  done
  cmd_inventory
  info "next: 'make ping' to check that Ansible reaches every VM"
}

cmd_list() { mp list; }

cmd_ssh() {
  local name="${1:-}" ip
  [[ -n "$name" ]] || die "usage: vms/vms.sh ssh NAME" 2
  ip="$(ip_of "$name")"
  [[ -n "$ip" ]] || die "$name has no IPv4 address" 2
  exec ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new "ubuntu@$ip"
}

cmd_down() {
  local spec name ip answer list
  read -r -p "Delete all the lab VMs for good? [y/N] " answer
  [[ "$answer" =~ ^[yY]$ ]] || { info "nothing deleted"; return 0; }
  list="$(vm_ips)" || die "could not list the VMs - is Multipass running?" 2
  for spec in "${NODES[@]}"; do
    name="${spec%%:*}"
    ip="$(awk -v n="$name" '$1 == n { print $2 }' <<<"$list")"
    [[ -n "$ip" ]] || continue
    # A recreated VM gets a new host key: forget the old one so SSH does not refuse it.
    [[ "$ip" == "-" ]] || forget_host_keys "$ip"
    mp delete --purge "$name"
    info "deleted $name"
  done
  rm -f -- "$INVENTORY"
}

case "${1:-}" in
  up) cmd_up ;;
  inventory) cmd_inventory ;;
  list) cmd_list ;;
  ssh) shift; cmd_ssh "$@" ;;
  down) cmd_down ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
