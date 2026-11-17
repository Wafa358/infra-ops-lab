SCRIPTS := $(wildcard scripts/*.sh scripts/lib/*.sh vms/*.sh)

.PHONY: all lint test vms vms-down inventory ping provision verify ansible-lint

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
