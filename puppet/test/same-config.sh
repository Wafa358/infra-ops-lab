#!/usr/bin/env bash
# same-config.sh - prove that the Puppet class demo_web and the Ansible role nginx write
# the same Nginx site, for web2 of ansible/inventory.example.ini. Only the first line
# ("Managed by ...") may differ. Also compiles the whole Puppet code in no-op mode.
set -euo pipefail
cd "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

echo "== puppet apply --noop with the example data (puppet/data/lab.example.yaml)"
puppet apply --noop --hiera_config=puppet/test/hiera.yaml --modulepath=puppet/modules \
  --confdir="$tmp/conf" --vardir="$tmp/var" --publicdir="$tmp/public" --rundir="$tmp/run" \
  --logdir="$tmp/log" puppet/manifests/site.pp > "$tmp/noop.log" 2>&1 \
  || { cat -- "$tmp/noop.log"; exit 1; }
echo "compiles and runs"

echo "== the site file written by each tool"
# The same values as puppet/data/lab.example.yaml and data/common.yaml.
puppet epp render puppet/modules/demo_web/templates/site.conf.epp --values "{
  server_names    => ['www.lab.internal', 'web2.lab.internal'],
  trusted_proxies => ['10.97.0.14'],
  served_by       => 'web2',
  app_port        => 8000,
  access_log      => '/var/log/nginx/demo-app.access.log',
}" > "$tmp/puppet.conf" 2> "$tmp/epp.log" || { cat -- "$tmp/epp.log"; exit 1; }
( cd ansible && ANSIBLE_LOCALHOST_WARNING=False ansible web2 -i inventory.example.ini -c local \
    -m ansible.builtin.template -a "src=roles/nginx/templates/demo-app.conf.j2 dest=$tmp/ansible.conf" \
    > "$tmp/ansible.log" 2>&1 ) || { cat -- "$tmp/ansible.log"; exit 1; }

if diff -u <(tail -n +2 "$tmp/ansible.conf") <(tail -n +2 "$tmp/puppet.conf"); then
  echo "identical (apart from the 'Managed by' line)"
else
  echo "the Puppet and Ansible versions differ (diff above)" >&2
  exit 1
fi
