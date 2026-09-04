#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
mode="${SUCACENTER_REPLICATION_MODE:-validate}"
case "$mode" in setup|validate|status) ;; *) die "Use replication setup|validate|status" ;; esac
[[ "$mode" != setup || "${SUCACENTER_NO_INSTALL:-0}" != 1 ]] || die "--no-install prevents replication setup."
for tool in python3 ssh ansible-playbook ansible-inventory; do need "$tool"; done
inventory="${SUCACENTER_INVENTORY:-$ROOT/ansible/inventory.ini}"
[[ -s "$inventory" ]] || die "Inventory missing: $inventory"
ansible-inventory -i "$inventory" --list | python3 -c '
import json, sys
d=json.load(sys.stdin)
def members(g, seen=None):
    seen=set() if seen is None else seen
    if g in seen: return set()
    seen.add(g)
    entry=d.get(g,{})
    result=set(entry.get("hosts",[]))
    for c in entry.get("children",[]): result |= members(c,seen)
    return result
assert members("controller")=={"worker01"}, "controller must contain worker01 only"
assert {"worker01","worker02"} <= members("workers"), "Missing workers"
h=d["_meta"]["hostvars"]
assert h["worker01"].get("ansible_host")=="192.168.1.110", "worker01 IP differs"
assert h["worker02"].get("ansible_host")=="192.168.1.103", "worker02 IP differs"
'
playbook="$ROOT/ansible/replication.yml"
[[ "$mode" != status ]] || playbook="$ROOT/ansible/replication-status.yml"
ansible-playbook -i "$inventory" "$playbook" --syntax-check
if [[ "$mode" == validate ]]; then
    printf 'Syntax and inventory validated. No hosts changed.\n'
elif [[ "$mode" == status ]]; then
    ansible-playbook -i "$inventory" "$playbook"
else
    ansible-playbook -i "$inventory" "$playbook" --ask-become-pass
fi
