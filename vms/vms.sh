#!/usr/bin/env bash
# vms.sh - create, list and delete the lab VMs with Multipass, from WSL.
#
# Usage:
#   vms/vms.sh up          create web1, db1 and mon1 (existing ones are kept) and write ansible/inventory.ini
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
IMAGE="24.04"
INVENTORY="$REPO_DIR/ansible/inventory.ini"
# name:cpus:memory:disk
NODES=("web1:1:1G:8G" "db1:1:1G:8G" "mon1:1:2G:10G")

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

exists() { mp info "$1" >/dev/null 2>&1; }

# ip_of NAME : first IPv4 address of a VM, empty if it has none (yet).
ip_of() {
  mp info "$1" --format json | python3 -c '
import json, sys
name = sys.argv[1]
info = json.load(sys.stdin).get("info", {}).get(name, {})
print((info.get("ipv4") or [""])[0])' "$1"
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
  local spec name ip
  {
    echo "# Written by vms/vms.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ) - do not edit, run 'make inventory'."
    for spec in "${NODES[@]}"; do
      name="${spec%%:*}"
      ip="$(ip_of "$name" 2>/dev/null || true)"
      if [[ -z "$ip" ]]; then
        warn "$name has no IPv4 address (is it running?) - left out of the inventory"
        continue
      fi
      # group = name without its number: web1 -> [web]
      printf '[%s]\n%s ansible_host=%s\n\n' "${name%%[0-9]*}" "$name" "$ip"
    done
    printf '[lab:children]\nweb\ndb\nmon\n'
  } > "$INVENTORY"
  info "wrote $INVENTORY"
  cat -- "$INVENTORY"
}

cmd_up() {
  local spec name cpus mem disk
  ensure_key
  for spec in "${NODES[@]}"; do
    IFS=: read -r name cpus mem disk <<<"$spec"
    if exists "$name"; then
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
  exec ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$ip"
}

cmd_down() {
  local spec name ip answer
  read -r -p "Delete web1, db1 and mon1 for good? [y/N] " answer
  [[ "$answer" =~ ^[yY]$ ]] || { info "nothing deleted"; return 0; }
  for spec in "${NODES[@]}"; do
    name="${spec%%:*}"
    exists "$name" || continue
    ip="$(ip_of "$name" 2>/dev/null || true)"
    # A recreated VM gets a new host key: forget the old one so SSH does not refuse it.
    if [[ -n "$ip" ]]; then ssh-keygen -R "$ip" >/dev/null 2>&1 || true; fi
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
