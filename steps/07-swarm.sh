#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
exec bash "$C/scripts/cluster-swarm" setup
