#!/usr/bin/env bash
# Entrada única. As etapas são reexecutáveis e só recebem OK após exit 0.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
export SUCACENTER_ROOT="$ROOT"
source "$ROOT/lib/common.sh"
action="${1:-help}"; if (($#)); then shift; fi
export SUCACENTER_NO_INSTALL=0 SUCACENTER_ALL=1 SUCACENTER_GRANT=0
with_services=0
target=""
while (($#)); do
  case "$1" in
    --no-install) export SUCACENTER_NO_INSTALL=1 ;;
    --local) export SUCACENTER_ALL=0 ;;
    --all) export SUCACENTER_ALL=1 ;;
    --grant-docker-access) export SUCACENTER_GRANT=1 ;;
    --services) with_services=1 ;;
    *) if [[ -z "$target" ]]; then target="$1"; else die "Argumento inesperado: $1"; fi ;;
  esac
  shift
done
run_step() {
  local name="$1" file="$ROOT/steps/$1.sh" stamp log
  [[ -f "$file" ]] || die "Etapa desconhecida: $name"
  mkdir -p "$C/logs" "$C/config/state"
  stamp=$(date +%Y%m%d-%H%M%S)
  log="$C/logs/$stamp-$name.log"
  if [[ "$SUCACENTER_NO_INSTALL" == 1 && "$name" =~ ^(02-dependencies|05-distcc|07-swarm)$ ]]; then
    echo "SKIPPED $name (--no-install)"
    printf 'skipped\n' > "$C/config/state/$name"
    return
  fi
  printf 'running\n' > "$C/config/state/$name"
  echo "=== $name ==="
  if bash "$file" 2>&1 | tee "$log"; then
    if [[ "$name" == 06-docker && "$SUCACENTER_NO_INSTALL" == 1 ]]; then
      printf 'prepared-only\n' > "$C/config/state/$name"
    elif [[ "$name" == 08-services && "${SUCACENTER_SERVICES_MODE:---validate}" == --prepare ]]; then
      printf 'prepared-only\n' > "$C/config/state/$name"
    elif [[ "$name" == 08-services && "${SUCACENTER_SERVICES_MODE:---validate}" == --validate ]]; then
      printf 'validated-only\n' > "$C/config/state/$name"
    elif [[ "$name" == 09-replication ]]; then
      printf '%s\n' "${SUCACENTER_REPLICATION_MODE:-validate}-completed" > "$C/config/state/$name"
    else
      printf 'ok\n' > "$C/config/state/$name"
    fi
  else
    printf 'failed\n' > "$C/config/state/$name"
    die "Etapa $name incompleta. Log: $log. Corrija e repita setup ou step $name."
  fi
}
case "$action" in
  setup)
    if [[ "$with_services" == 1 ]]; then
      [[ "$SUCACENTER_ALL" == 1 ]] || die "--services requer setup no manager, sem --local."
      [[ "$SUCACENTER_NO_INSTALL" == 0 ]] || die "Use services prepare para apenas coletar arquivos."
      for tool in ansible ansible-inventory ansible-playbook; do need "$tool"; done
    fi
    for name in 01-preflight 04-workspace 02-dependencies 03-ssh 05-distcc 06-docker; do run_step "$name"; done
    if [[ "$SUCACENTER_ALL" == 1 ]]; then run_step 07-swarm; fi
    if [[ "$with_services" == 1 ]]; then
      export SUCACENTER_SERVICES_MODE=--run
      run_step 08-services
    fi
    echo "Etapas finalizadas. Estado: $C/config/state. Valide: bash sucacenter.sh doctor"
    ;;
  step)
    case "$target" in
      preflight) target=01-preflight;; dependencies) target=02-dependencies;;
      ssh) target=03-ssh;; workspace) target=04-workspace;; distcc) target=05-distcc;;
      docker) target=06-docker;; swarm) target=07-swarm;;
      services) target=08-services;;
      replication) target=09-replication;;
    esac
    run_step "$target" ;;
  services)
    case "${target:-validate}" in
      prepare|validate|run) export SUCACENTER_SERVICES_MODE="--${target:-validate}" ;;
      *) die "Use services prepare|validate|run" ;;
    esac
    if [[ "$SUCACENTER_NO_INSTALL" == 1 && "$SUCACENTER_SERVICES_MODE" == --run ]]; then
      die "--no-install nao permite services run; use services prepare."
    fi
    run_step 08-services ;;
  replication)
    case "${target:-validate}" in
      setup|validate|status) export SUCACENTER_REPLICATION_MODE="${target:-validate}" ;;
      *) die "Use replication setup|validate|status" ;;
    esac
    [[ "$SUCACENTER_REPLICATION_MODE" != setup || "$SUCACENTER_NO_INSTALL" != 1 ]] || die "--no-install prevents replication setup."
    run_step 09-replication ;;
  doctor|status) bash "$ROOT/commands/cluster" "$action" ;;
  test)
    case "$target" in
      unit) bash "$ROOT/tests/unit.sh" ;;
      distcc) bash "$ROOT/tests/distcc-live.sh" ;;
      benchmark) bash "$ROOT/tests/benchmark-distcc.sh" ;;
      swarm) bash "$ROOT/tests/swarm-live.sh" ;;
      *) die "Use test unit|distcc|benchmark|swarm" ;;
    esac ;;
  help|--help|-h)
    cat <<'HELP'
SucaCenter 1.2.0 — Debian/Ubuntu/Linux Mint com systemd
  bash sucacenter.sh replication validate         Validar sintaxe e inventory (sem acesso remoto)
  bash sucacenter.sh replication setup            Replica automatica + historico de 30 dias
  bash sucacenter.sh replication status           Verificar conexao, progresso e erros
  bash sucacenter.sh services prepare            Coletar playbooks e inventory, com backup
  bash sucacenter.sh services validate           Inventory, syntax-check e ping Ansible
  bash sucacenter.sh services run                Slurm, NFS, Samba, Gitea e healthcheck
  bash sucacenter.sh setup --services            Setup base + Swarm + servicos Ansible
  bash sucacenter.sh setup --grant-docker-access   Setup completo master + workers + Swarm
  bash sucacenter.sh setup --no-install           Preparação sem instalar/configurar serviços
  bash sucacenter.sh setup --local                Preparar somente esta máquina (sem Swarm)
  bash sucacenter.sh step docker --grant-docker-access
  bash sucacenter.sh step distcc
  bash sucacenter.sh step swarm
  bash sucacenter.sh doctor
  bash sucacenter.sh status
  bash sucacenter.sh test unit|distcc|swarm

Config: ~/cluster/config/settings.env e ~/cluster/nodes (preservados).
Acesso SSH e sudo já autorizados são pré-requisitos; veja docs/instalacao.md.
O grupo docker equivale a root; só é concedido por --grant-docker-access.
--no-install não configura distcc/Swarm e não marca essas etapas como concluídas.
HELP
    ;;
  *) die "Comando desconhecido: $action" ;;
esac
