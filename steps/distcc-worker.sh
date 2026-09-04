#!/usr/bin/env bash
# Auxiliar remoto. Limita o daemon à interface LAN e ao IP do master.
set -euo pipefail
export LC_ALL=C
master="${1:?master}"; peer="${2:?worker}"; slots="${3:?slots}"
for address in "$master" "$peer"; do
  [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
done
[[ "$slots" =~ ^[1-9][0-9]*$ ]] || exit 2
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
apt-get update
apt-get install -y --no-remove distcc ccache build-essential
file=/etc/default/distcc
[[ -e "$file" ]] || { echo "Configuração esperada ausente: $file"; exit 1; }
cp -a "$file" "$file.sucacenter-$(date +%Y%m%d-%H%M%S)-$$.bak"
# Substitui somente as quatro chaves conhecidas; mantém demais opções.
for key in STARTDISTCC ALLOWEDNETS LISTENER JOBS; do
  case "$key" in
    STARTDISTCC) value=true;; ALLOWEDNETS) value="127.0.0.1 $master";;
    LISTENER) value="$peer";; JOBS) value="$slots";;
  esac
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=\"$value\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
done
if command -v ufw >/dev/null && [[ $(ufw status) == *"Status: active"* ]]; then
  ufw allow from "$master" to "$peer" port 3632 proto tcp comment SucaCenter-distcc
fi
systemctl enable distcc
systemctl restart distcc
ss -ltn | grep -F "$peer:3632"
