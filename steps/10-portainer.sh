#!/usr/bin/env bash
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"

mode="${SUCACENTER_PORTAINER_MODE:-validate}"
stack="$SUCACENTER_ROOT/stacks/portainer.yml"
stack_name=portainer

need docker
[[ -r "$stack" ]] || die "Stack ausente: $stack"
docker info >/dev/null 2>&1 || die "Docker indisponivel para esta conta. Use --grant-docker-access ou sudo conforme a documentacao."
read -r swarm_state manager_access < <(docker info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}')
[[ "$swarm_state" == active && "$manager_access" == true ]] || die "Execute no manager ativo do Swarm (worker01)."

echo "Validando stacks/portainer.yml..."
docker stack config -c "$stack" >/dev/null

if [[ "$mode" == validate ]]; then
  echo "OK: stack valida; nenhuma alteracao realizada."
  exit 0
fi

show_status() {
  local services
  services=$(docker stack services "$stack_name" --format '{{.Name}} {{.Mode}} {{.Replicas}} {{.Image}}' 2>/dev/null) || \
    die "Stack portainer ainda nao esta instalada."
  printf '%s\n' "$services"
  if command -v curl >/dev/null 2>&1 && curl -kfsS --connect-timeout 4 https://127.0.0.1:9443/api/status >/dev/null; then
    echo "HTTPS OK: https://${SUCACENTER_MANAGER_IP}:9443"
  else
    die "Servicos encontrados, mas a API HTTPS em 9443 nao respondeu."
  fi
}

if [[ "$mode" == status ]]; then
  show_status
  exit 0
fi

mapfile -t existing < <(docker stack services "$stack_name" --format '{{.Name}}' 2>/dev/null || true)
for service in "${existing[@]}"; do
  case "$service" in
    portainer_agent|portainer_portainer) ;;
    *) die "Servico inesperado no stack portainer: $service. Revise antes de atualizar." ;;
  esac
done

if ((${#existing[@]} == 0)) && command -v ss >/dev/null 2>&1 && ss -H -ltn 'sport = :9443' | grep -q .; then
  die "Porta 9443 ja esta em uso e nao pertence ao stack portainer."
fi

active_nodes=$(docker node ls --filter node.label=portainer.io/agent=true --filter availability=active --format '{{.ID}}' | wc -l)
if ((active_nodes == 0)); then
  active_nodes=$(docker node ls --filter availability=active --format '{{.ID}}' | wc -l)
fi
((active_nodes >= 1)) || die "Nenhum no ativo no Swarm."

echo "Instalando/atualizando Portainer no Swarm..."
docker stack deploy --resolve-image always -c "$stack" "$stack_name"

deadline=$((SECONDS + 120))
while ((SECONDS < deadline)); do
  server=$(docker service ls --filter name=portainer_portainer --format '{{.Replicas}}' | head -n1)
  agents=$(docker service ls --filter name=portainer_agent --format '{{.Replicas}}' | head -n1)
  agent_running="${agents%/*}"
  agent_desired="${agents#*/}"
  if [[ "$server" == 1/1 && "$agent_running" =~ ^[0-9]+$ && "$agent_running" == "$agent_desired" && "$agent_running" -ge 1 ]]; then
    show_status
    echo "Abra https://${SUCACENTER_MANAGER_IP}:9443 e crie o administrador inicial."
    exit 0
  fi
  sleep 3
done
die "Portainer nao convergiu em 120s. Execute: bash sucacenter.sh portainer status"
