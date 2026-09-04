#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
mode="${SUCACENTER_SERVICES_MODE:---validate}"
[[ "$SUCACENTER_MANAGER_IP" == 192.168.1.110 ]] || die "Os playbooks fornecidos requerem manager 192.168.1.110."
# Prefer the reviewed merged bundle. Explicit source overrides still work.
export SUCACENTER_SOURCE_DIR="${SUCACENTER_SOURCE_DIR:-$ROOT/ansible/playbooks}"
export SUCACENTER_INVENTORY="${SUCACENTER_INVENTORY:-$ROOT/ansible/inventory.ini}"
[[ "$mode" != --run || "${SUCACENTER_NO_INSTALL:-0}" != 1 ]] || die "--no-install nao permite provisionamento."
exec bash "$ROOT/ansible/bootstrap-sucacenter.sh" "$mode"
