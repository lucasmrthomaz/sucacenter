#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
[[ "$SUCACENTER_ALL" == 1 ]] || exit 0
# Não substitui chaves nem aceita fingerprints automaticamente.
while IFS= read -r host; do
  echo "Verificando SSH: $host"
  remote "$host" bash -c 'command -v bash && command -v python3 && uname -m'
  remote "$host" mkdir -p cluster/app
  # Pacote operacional: lista explícita, sem .git ou configurações privadas.
  tar -C "$ROOT" -czf - lib commands steps tests docs ansible config/nodes.example config/settings.example.env sucacenter.sh |
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'tar -xzf - -C "$HOME/cluster/app"'
  flags='--local'
  [[ "$SUCACENTER_NO_INSTALL" != 1 ]] || flags="$flags --no-install"
  [[ "$SUCACENTER_GRANT" != 1 ]] || flags="$flags --grant-docker-access"
  command="bash \"\$HOME/cluster/app/sucacenter.sh\" setup $flags"
  if [[ -t 0 ]]; then ssh -tt "$host" "$command"; else ssh -n "$host" "$command"; fi
done < <(nodes)
echo "SSH verificado. Primeira autorização de chave: docs/instalacao.md."
