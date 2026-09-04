#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
mkdir -p "$HOME/bin" "$C"/{logs,jobs,shared-files,workloads,config,archives,output,scripts,app}
[[ -e "$C/nodes" ]] || cp "$ROOT/config/nodes.example" "$C/nodes"
[[ -e "$C/config/settings.env" ]] || cp "$ROOT/config/settings.example.env" "$C/config/settings.env"
# Instala cópia operacional sem .git, credenciais, configurações ou dados locais.
if [[ "$(realpath "$ROOT")" != "$(realpath "$C/app")" ]]; then
  for part in lib commands steps config tests docs ansible stacks; do
    mkdir -p "$C/app/$part"
    cp -a "$ROOT/$part/." "$C/app/$part/"
  done
  cp "$ROOT/sucacenter.sh" "$C/app/sucacenter.sh"
fi
for command in cluster-docker cluster-swarm; do
  cp "$ROOT/commands/$command" "$C/scripts/$command"
  chmod +x "$C/scripts/$command"
  ln -sfn "$C/scripts/$command" "$HOME/bin/$command"
done
chmod +x "$C/app/commands/cluster"
for name in help init run exec status info health doctor burn sync-push sync-pull shared-status \
  verify checksum archive compress decompress image-convert image-resize image-optimize video audio \
  build build-c build-cpp build-rust build-go build-zig build-node build-dotnet build-java \
  test lint capabilities inventory update install clean reboot shutdown logs jobs queue; do
  ln -sfn "$C/app/commands/cluster" "$HOME/bin/cluster-$name"
done
for name in cluster-docker-status cluster-compose; do
  ln -sfn "$C/scripts/cluster-docker" "$HOME/bin/$name"
done
ln -sfn "$C/app/sucacenter.sh" "$HOME/bin/sucacenter"
chmod +x "$C/app/sucacenter.sh"
line='export PATH="$HOME/bin:$HOME/.local/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  grep -Fqx "$line" "$rc" 2>/dev/null || printf '\n# SucaCenter\n%s\n' "$line" >> "$rc"
done
echo "Workspace e comandos instalados. Abra nova sessão ou export PATH=\"\$HOME/bin:\$PATH\"."
