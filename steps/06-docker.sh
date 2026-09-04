#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
args=(setup)
[[ "$SUCACENTER_ALL" != 1 ]] || args+=(--all)
[[ "$SUCACENTER_NO_INSTALL" != 1 ]] || args+=(--no-install)
[[ "$SUCACENTER_GRANT" != 1 ]] || args+=(--grant-docker-access)
bash "$C/scripts/cluster-docker" "${args[@]}"
