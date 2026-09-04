#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
[[ $(uname -s) == Linux ]] || die "O instalador roda em Linux. No Windows apenas extraia o pacote."
(( BASH_VERSINFO[0] >= 4 )) || die "Bash 4 ou posterior necessário."
(( EUID != 0 )) || die "Execute como usuário operacional; sudo é usado somente nas etapas de sistema."
for tool in bash python3 ssh scp; do need "$tool"; done
python3 -c 'import sys; assert sys.version_info >= (3,9), "Python 3.9+ necessário"'
nodes >/dev/null
[[ "$LOCAL_SLOTS" =~ ^[1-9][0-9]*$ && "$WORKER_SLOTS" =~ ^[1-9][0-9]*$ ]] || die "Slots devem ser inteiros positivos."
echo "Host: $(hostname); CPU: $(uname -m); conta: $(id -un)"
free -h
echo "Pré-requisitos básicos OK. SSH e sudo serão verificados nas etapas próprias."
