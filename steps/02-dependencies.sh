#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
need apt-get
# Sem upgrade global, remoção de pacotes ou inclusão de repositórios externos.
packages=(openssh-client openssh-server rsync parallel build-essential ccache distcc
  python3 ffmpeg imagemagick tar gzip xz-utils zstd shellcheck curl)
sudo_cmd apt-get update
sudo_cmd apt-get install -y --no-remove "${packages[@]}"
echo "Dependências base instaladas. Toolchains adicionais: docs/comandos.md."
