#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
[[ "$SUCACENTER_ALL" == 1 ]] || { echo "distcc é configurado a partir do master."; exit 0; }
need rsync
local_version=$(gcc -dumpfullversion)
for host in $(nodes); do
  peer="${host##*@}"
  [[ "$peer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "distcc requer hosts IPv4 explícitos: $host"
  remote "$host" mkdir -p cluster/app/steps
  scp -q "$ROOT/steps/distcc-worker.sh" "$host:cluster/app/steps/distcc-worker.sh"
  printf -v quoted 'bash "$HOME/cluster/app/steps/distcc-worker.sh" %q %q %q' "$MANAGER_IP" "$peer" "$WORKER_SLOTS"
  if [[ -t 0 ]]; then ssh -tt "$host" "$quoted"; else ssh -n "$host" "$quoted"; fi
  version=$(remote "$host" gcc -dumpfullversion)
  [[ "$version" == "$local_version" ]] || die "GCC incompatível: master=$local_version; $host=$version"
done
hosts="localhost/$LOCAL_SLOTS"
while read -r host; do hosts="$hosts ${host##*@}/$WORKER_SLOTS"; done < <(nodes)
printf '%s\n' "$hosts" > "$C/config/distcc-hosts"
echo "distcc configurado. Valide: bash sucacenter.sh test distcc"
