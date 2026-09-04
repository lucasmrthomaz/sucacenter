#!/usr/bin/env bash
# Biblioteca: paths fixos no HOME da conta operacional, nunca da conta sudo.
C="$HOME/cluster"
ROOT="${SUCACENTER_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
export SUCACENTER_ROOT="$ROOT"
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export LC_ALL=C
die(){ echo "ERRO: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Dependência ausente: $1"; }
MANAGER_IP="${SUCACENTER_MANAGER_IP:-192.168.1.110}"
LOCAL_SLOTS=2; WORKER_SLOTS=4
if [[ -f "$C/config/settings.env" ]]; then source "$C/config/settings.env"; fi
export SUCACENTER_MANAGER_IP="$MANAGER_IP"
nodes() {
  local n
  [[ -f "$C/nodes" ]] || return 0
  while IFS= read -r n || [[ -n "$n" ]]; do
    n="${n%$'\r'}"
    [[ -z "$n" || "$n" == \#* || "$n" == : ]] && continue
    [[ "$n" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.@-]*$ ]] || die "Host inválido: $n"
    printf '%s\n' "$n"
  done < "$C/nodes"
}
remote() {
  local host="$1" quoted; shift
  printf -v quoted '%q ' "$@"
  ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$host" "$quoted"
}
sudo_cmd() {
  if (( EUID == 0 )); then "$@"; else sudo "$@"; fi
}
