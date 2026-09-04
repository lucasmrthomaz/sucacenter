#!/usr/bin/env bash
# Compila só no worker, sem fallback nem ccache. Não é benchmark.
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
need distcc; need gcc
host=$(nodes | head -n1)
[[ -n "$host" ]] || die "Nenhum worker configurado."
dir=$(mktemp -d "$C/workloads/distcc-test.XXXXXX")
printf 'int main(void) { return 0; }\n' > "$dir/test.c"
DISTCC_HOSTS="${host##*@}/1" DISTCC_FALLBACK=0 DISTCC_VERBOSE=1 \
  distcc gcc -c "$dir/test.c" -o "$dir/test.o"
gcc "$dir/test.o" -o "$dir/test"
"$dir/test"
echo "OK: compilação remota e execução local. Arquivos: $dir"
