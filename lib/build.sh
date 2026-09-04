#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
action="$1"; shift
if [[ "$action" == build ]]; then lang="${1:?linguagem}"; shift
elif [[ "$action" == build-* ]]; then lang="${action#build-}"
else lang=""; fi
dir="${1:-.}"; if (($#)); then shift; fi
cd -- "$dir"
if [[ "$action" == test || "$action" == lint ]]; then
  if [[ -f Cargo.toml ]]; then
    if [[ "$action" == test ]]; then exec cargo test "$@"; else exec cargo clippy "$@"; fi
  elif [[ -f go.mod ]]; then
    if [[ "$action" == test ]]; then exec go test ./... "$@"; else exec go vet ./... "$@"; fi
  elif [[ -f package.json ]]; then exec npm run "$action" -- "$@"
  elif [[ -f build.zig ]]; then
    if [[ "$action" == test ]]; then exec zig build test "$@"; else exec zig fmt --check . "$@"; fi
  elif compgen -G '*.csproj' >/dev/null || compgen -G '*.sln' >/dev/null; then
    if [[ "$action" == test ]]; then exec dotnet test "$@"; else exec dotnet format --verify-no-changes "$@"; fi
  elif [[ -f pom.xml ]]; then
    if [[ "$action" == test ]]; then exec mvn test "$@"; else exec mvn verify -DskipTests "$@"; fi
  elif [[ -f gradlew || -f build.gradle || -f build.gradle.kts ]]; then
    task=test; [[ "$action" == test ]] || task=check
    if [[ -f gradlew ]]; then exec bash gradlew "$task" "$@"; else exec gradle "$task" "$@"; fi
  elif [[ -f Makefile ]]; then exec make "$action" "$@"
  else die "Projeto/runner não reconhecido."; fi
fi
case "$lang" in
  c|cpp)
    need ccache; need distcc
    if [[ -z "${DISTCC_HOSTS:-}" ]]; then
      [[ -f "$C/config/distcc-hosts" ]] || die "Configure primeiro a etapa distcc ou DISTCC_HOSTS."
      export DISTCC_HOSTS="$(< "$C/config/distcc-hosts")"
    fi
    # ccache reconhece GCC como compilador; distcc é o prefixo para cache misses.
    export CCACHE_PREFIX=distcc
    exec make -j"${JOBS:-$LOCAL_SLOTS}" CC='ccache gcc' CXX='ccache g++' "$@" ;;
  rust) exec cargo build "$@" ;;
  go) exec go build "$@" ;;
  zig) exec zig build "$@" ;;
  node) exec npm run build -- "$@" ;;
  dotnet) exec dotnet build "$@" ;;
  java)
    if [[ -f pom.xml ]]; then exec mvn package "$@"
    elif [[ -f gradlew ]]; then exec bash gradlew build "$@"
    else exec gradle build "$@"; fi ;;
  *) die "Linguagem desconhecida: $lang" ;;
esac
