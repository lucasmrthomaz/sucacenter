#!/usr/bin/env bash
# Zero-touch entry point for a new Debian/Ubuntu machine.
set -euo pipefail
umask 077

REPOSITORY="${SUCACENTER_REPOSITORY:-https://github.com/lucasmrthomaz/sucacenter.git}"
REF="${SUCACENTER_REF:-main}"
INSTALL_DIR="${SUCACENTER_INSTALL_DIR:-$HOME/.local/share/sucacenter}"
MODE="${1:---run}"

case "$MODE" in --prepare|--validate|--run) ;; *) echo "usage: bootstrap.sh [--prepare|--validate|--run]" >&2; exit 2;; esac

install_dependencies() {
  local packages=(git openssh-client python3 python3-pip ansible rsync tar)
  if command -v apt-get >/dev/null 2>&1; then
    sudo -n true 2>/dev/null || sudo -v
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  else
    echo "ERROR: automatic dependency installation currently supports Debian/Ubuntu (apt)." >&2
    exit 1
  fi
}

for dependency in git ssh python3 ansible-playbook ansible-inventory rsync tar; do
  if ! command -v "$dependency" >/dev/null 2>&1; then install_dependencies; break; fi
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
  mkdir -p "$(dirname "$INSTALL_DIR")"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" fetch --prune origin
    git -C "$INSTALL_DIR" checkout "$REF"
    git -C "$INSTALL_DIR" pull --ff-only origin "$REF"
  else
    git clone --branch "$REF" "$REPOSITORY" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/bootstrap.sh" "$MODE"
fi

ROOT="$SCRIPT_DIR"
INVENTORY="$ROOT/ansible/inventory.local.ini"
CONFIG="$ROOT/config/config.local.yml"
mkdir -p "$ROOT/secrets" "$ROOT/backups" "$HOME/.local/bin" "$HOME/.ssh" "$HOME/.config/sucacenter"
chmod 700 "$ROOT/secrets" "$ROOT/backups" "$HOME/.ssh"

controller_ip="${SUCACENTER_CONTROLLER:-}"
if [[ -z "$controller_ip" ]]; then
  controller_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  controller_ip="${controller_ip:-127.0.0.1}"
fi
ssh_user="${SUCACENTER_SSH_USER:-${SUDO_USER:-$USER}}"
controller_name="$(hostname -s | tr -cs 'A-Za-z0-9_.-' '-')"
network_cidr="${SUCACENTER_NETWORK_CIDR:-$(awk -F. '{if (NF == 4) print $1"."$2"."$3".0/24"; else print "127.0.0.0/8"}' <<<"$controller_ip")}" 

if [[ ! -f "$HOME/.ssh/sucacenter_ed25519" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'sucacenter-bootstrap' -f "$HOME/.ssh/sucacenter_ed25519"
fi

{
  echo '[controller]'
  if [[ "$controller_ip" == 127.* || "$controller_ip" == "$(hostname -I 2>/dev/null | awk '{print $1}')" ]]; then
    printf '%s ansible_host=%s ansible_connection=local\n' "$controller_name" "$controller_ip"
  else
    printf '%s ansible_host=%s\n' "$controller_name" "$controller_ip"
  fi
  echo
  echo '[workers]'
  echo "$controller_name"
  IFS=',' read -ra workers <<<"${SUCACENTER_WORKERS:-}"
  index=1
  for worker in "${workers[@]}"; do
    [[ -n "$worker" ]] || continue
    worker_user="$ssh_user"; worker_host="$worker"
    if [[ "$worker" == *@* ]]; then worker_user="${worker%@*}"; worker_host="${worker#*@}"; fi
    printf 'worker%02d ansible_host=%s ansible_user=%s\n' "$index" "$worker_host" "$worker_user"
    index=$((index + 1))
  done
  echo; echo '[cluster:children]'; echo 'controller'; echo 'workers'
  echo; echo '[cluster:vars]'
  printf 'ansible_user=%s\nansible_python_interpreter=/usr/bin/python3\n' "$ssh_user"
  printf 'ansible_ssh_private_key_file=%s\n' "$HOME/.ssh/sucacenter_ed25519"
} >"$INVENTORY"

if [[ -n "${SUCACENTER_BECOME_PASSWORD:-}" ]]; then
  SUCACENTER_SECRET_FILE="$ROOT/secrets/vars.yml" python3 - <<'PY'
import json
import os
from pathlib import Path
Path(os.environ["SUCACENTER_SECRET_FILE"]).write_text(
    "ansible_become_password: " + json.dumps(os.environ["SUCACENTER_BECOME_PASSWORD"]) + "\n",
    encoding="utf-8",
)
PY
  chmod 600 "$ROOT/secrets/vars.yml"
fi

if [[ -n "${SUCACENTER_SSH_PASSWORD:-}" && -n "${SUCACENTER_WORKERS:-}" ]]; then
  command -v sshpass >/dev/null 2>&1 || { sudo apt-get update; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y sshpass; }
  export SSHPASS="$SUCACENTER_SSH_PASSWORD"
  for worker in "${workers[@]}"; do
    [[ -n "$worker" ]] || continue
    [[ "$worker" == *@* ]] || worker="$ssh_user@$worker"
    ssh-keyscan -H "${worker#*@}" >>"$HOME/.ssh/known_hosts" 2>/dev/null
    sshpass -e ssh-copy-id -i "$HOME/.ssh/sucacenter_ed25519.pub" "$worker"
  done
  unset SSHPASS
fi

sed -e "s|sucacenter_controller_address:.*|sucacenter_controller_address: $controller_ip|" \
    -e "s|sucacenter_network_cidr:.*|sucacenter_network_cidr: $network_cidr|" \
    -e "s|sucacenter_ssh_user:.*|sucacenter_ssh_user: $ssh_user|" \
    "$ROOT/config/config.example.yml" >"$CONFIG"

install -m 0755 "$ROOT/tools/suca" "$HOME/.local/bin/suca"
printf '%s\n' "$ROOT" >"$HOME/.config/sucacenter/root"
ansible-galaxy collection install -r "$ROOT/ansible/requirements.yml"

echo "Prepared local inventory for controller $controller_name ($controller_ip)."
echo "Command installed at $HOME/.local/bin/suca (add $HOME/.local/bin to PATH if needed)."
[[ "$MODE" == --prepare ]] && exit 0
"$HOME/.local/bin/suca" validate
[[ "$MODE" == --validate ]] && exit 0
"$HOME/.local/bin/suca" apply
