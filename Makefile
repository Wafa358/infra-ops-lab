SCRIPTS := $(wildcard scripts/*.sh scripts/lib/*.sh vms/*.sh)

.PHONY: all lint test vms vms-down inventory ping provision verify ansible-lint vpn-up vpn-down vpn-status health

all: lint test

# --- step 1: Bash toolkit ---------------------------------------------------
lint:
	shellcheck -x $(SCRIPTS)

test:
	bats tests/

# --- step 2: VMs and Ansible --------------------------------------------------
vms:
	vms/vms.sh up

vms-down:
	vms/vms.sh down

inventory:
	vms/vms.sh inventory

ping:
	cd ansible && ansible lab -m ansible.builtin.ping

provision:
	cd ansible && ansible-playbook site.yml

verify:
	cd ansible && ansible-playbook verify.yml

ansible-lint:
	cd ansible && ansible-lint site.yml verify.yml

# --- step 3b: WireGuard VPN on the control node -------------------------------
VPN_CONF := $(CURDIR)/ansible/wg/wg-lab.conf

# (Re)start the tunnel: run it after 'make provision' and after every WSL restart.
vpn-up:
	@test -f $(VPN_CONF) || { echo "no $(VPN_CONF) yet: run 'make provision' first"; exit 1; }
	@sudo wg-quick down $(VPN_CONF) 2>/dev/null || true
	sudo wg-quick up $(VPN_CONF)

vpn-down:
	sudo wg-quick down $(VPN_CONF)

vpn-status:
	sudo wg show wg-lab

# --- step 4: the toolkit on the VMs -------------------------------------------
# Run the health check on every VM now and show its report.
health:
	cd ansible && ansible lab -b -m ansible.builtin.shell -a \
	  'systemctl start healthcheck.service; journalctl -u healthcheck.service -n 15 -o cat --no-pager | grep -E "^(OK|WARNING|CRITICAL|UNKNOWN|HEALTH)"'
