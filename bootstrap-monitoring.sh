#!/usr/bin/env bash
# SucaCenter: execute no MASTER com: bash bootstrap-monitoring.sh
# Debian / Ubuntu / MX Linux; amd64 e arm64; systemd ou SysVinit.
# Execute como seu usuario habitual para aproveitar suas chaves SSH e ssh-agent.
# Internet/APT nos nos; acesso SSH e sudo (ou root) nos remotos.
# HOSTS aceita IPv4 ou DNS, opcionalmente usuario@host, separados por espacos/virgulas.
# IPv6 literal nao e aceito; use um nome DNS. O master e incluido automaticamente.
# Exemplos: HOSTS="cluster@192.168.1.111 cluster@worker02"
# Variaveis de ambiente tambem sao aceitas. HOSTS="-" = somente master.
HOSTS="${HOSTS:-}"
SSH_USER="${SSH_USER:-${SUDO_USER:-$(id -un)}}"
SSH_PORT="${SSH_PORT:-22}"
GRAFANA_BIND="${GRAFANA_BIND:-0.0.0.0}"
GRAFANA_PORT="${GRAFANA_PORT:-}"
# Porta automatica: 3000; se ocupada (ex.: Gitea), 3001. Escolha persistida.
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:latest}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:latest}"
# Imagens sao fixadas por digest na primeira execucao, sem upgrade implicito.
# Para atualizar, remova /opt/sucacenter/monitoring/images.json e execute novamente.
# Node Exporter segue atualizacoes APT da distribuicao. Compose manual nao se autoatualiza.
# Rede confiavel/VPN: 9100 sem autenticacao nos nos; 3000 HTTP no master.
# Prometheus 9090 fica SOMENTE no loopback do master; nao ha alteracoes de firewall.
# Restrinja 9100 ao master no firewall. Para acesso publico ao Grafana, use proxy TLS.
# Configs anteriores: /opt/sucacenter/monitoring/backups; dados: volumes Docker.
# Reexecutar preserva dados, senha inicial e imagens. Dashboard provisionado e gerenciado.
# Diagnostico: sudo docker compose -p sucacenter-monitoring -f /opt/sucacenter/monitoring/docker-compose.yml logs --tail=100
# Fontes: https://docs.docker.com/compose/install/linux/
# https://grafana.com/docs/grafana/latest/administration/provisioning/
# https://prometheus.io/docs/guides/node-exporter/

set -Eeuo pipefail
set +x                         # Nunca rastrear credenciais.
umask 077
BASE=/opt/sucacenter/monitoring
WORK=""
REMOTE_TMP=""
REMOTE_DEST=""
declare -a SUDO=() SSH_OPTS=() CONNECTED=()
log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }
cleanup() {
    local rc=$?
    trap - EXIT
    if [[ -n "$REMOTE_TMP" && -n "$REMOTE_DEST" ]]; then
        ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$REMOTE_DEST" "rm -f -- '$REMOTE_TMP'" >/dev/null 2>&1 || true
    fi
    local dest
    for dest in "${CONNECTED[@]}"; do
        ssh "${SSH_OPTS[@]}" -O exit "$dest" >/dev/null 2>&1 || true
    done
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
    exit "$rc"
}
trap cleanup EXIT
trap 'printf "\nERRO na linha %s (codigo %s). Corrija a causa e execute novamente; os dados persistentes foram preservados.\n" "$LINENO" "$?" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "${1:-}" != --help && "${1:-}" != -h ]] || {
    sed -n '2,/^$/p' "$0"; exit 0;
}
[[ $# == 0 ]] || die 'Use bash bootstrap-monitoring.sh (sem argumentos), ou --help.'
[[ $(uname -s) == Linux ]] || die 'Execute este arquivo no master Linux.'
[[ -r /etc/debian_version ]] || die 'Este script requer Debian, Ubuntu ou derivada Debian (MX Linux).'
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) die 'Arquitetura suportada: x86_64 ou arm64.' ;; esac
[[ "$SSH_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*\$?$ ]] || die 'SSH_USER invalido.'
[[ "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535)) || die 'SSH_PORT invalida.'
if (( EUID != 0 )); then
    command -v sudo >/dev/null || die 'sudo ausente. Instale sudo ou execute como root com acesso SSH configurado.'
    log 'Validando privilegios locais (sudo pode pedir sua senha).'
    sudo -v
    SUDO=(sudo)
fi
command -v apt-get >/dev/null || die 'apt-get nao encontrado.'
if ! command -v flock >/dev/null; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends util-linux
fi
WORK=$(mktemp -d /tmp/suca-monitoring.XXXXXXXX)
# flock impede duas execucoes sobre a mesma instalacao, inclusive por usuarios diferentes.
"${SUDO[@]}" install -d -m 0755 "$BASE"
"${SUDO[@]}" touch "$BASE/.bootstrap.lock"
"${SUDO[@]}" chmod 0644 "$BASE/.bootstrap.lock"
exec 9<"$BASE/.bootstrap.lock"
flock -n 9 || die 'Outro bootstrap ja esta em execucao.'

log 'Checando dependencias locais.'
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl python3 openssh-client iproute2 util-linux
python3 - "$GRAFANA_BIND" <<'PY'
import ipaddress, sys
if ipaddress.ip_address(sys.argv[1]).version != 4:
    raise SystemExit('GRAFANA_BIND deve ser um IPv4 local ou 0.0.0.0.')
PY
if [[ -z "$HOSTS" ]]; then
    if "${SUDO[@]}" test -f "$BASE/hosts.txt"; then
        HOSTS=$("${SUDO[@]}" cat "$BASE/hosts.txt")
        log 'Reutilizando hosts salvos.'
    else
        [[ -r /dev/tty ]] || die 'Sem terminal. Defina HOSTS="usuario@host ..." ou HOSTS="-".'
        printf 'Hosts remotos (IPs/DNS, separados por espaco; Enter = somente master): ' >/dev/tty
        IFS= read -r HOSTS </dev/tty
        HOSTS=${HOSTS:--}
    fi
fi
python3 - "$HOSTS" "$SSH_USER" "$WORK" <<'PY'
import sys, re, json, pathlib, ipaddress, socket
raw, default, work = sys.argv[1:]
nodes = []
seen = set()
for token in ([] if raw.strip() == '-' else re.split(r'[\s,]+', raw.strip())):
    if not token: continue
    parts = token.split('@')
    if len(parts) == 1: user, host = default, parts[0]
    elif len(parts) == 2: user, host = parts
    else: raise SystemExit('Host invalido: ' + token)
    if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*\$?', user):
        raise SystemExit('Usuario SSH invalido: ' + user)
    if len(host) > 253 or not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?', host):
        raise SystemExit('Use IPv4 ou DNS valido, sem porta: ' + host)
    if host.lower() == 'localhost' or host.startswith('127.'):
        raise SystemExit('Nao inclua loopback: o master ja e monitorado automaticamente.')
    try: socket.getaddrinfo(host, 9100, type=socket.SOCK_STREAM)
    except OSError as exc: raise SystemExit(f'Nao foi possivel resolver {host}: {exc}')
    if host.lower() in seen: continue
    seen.add(host.lower())
    nodes.append(dict(user=user, host=host, node=host))
p = pathlib.Path(work)
(p/'nodes.json').write_text(json.dumps(nodes))
(p/'hosts.txt').write_text(' '.join(n['user']+'@'+n['host'] for n in nodes) or '-')
(p/'connections.txt').write_text(''.join(n['user']+'@'+n['host']+'\n' for n in nodes))
PY

# Instalador autonomo enviado por SCP: nenhuma senha transita em variaveis/arquivos.
cat >"$WORK/install-node.sh" <<'NODE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
trap 'printf "ERRO Node Exporter em %s, linha %s (codigo %s)\n" "$(hostname)" "$LINENO" "$?" >&2' ERR
[[ $EUID == 0 ]] || { echo 'Requer root/sudo.' >&2; exit 1; }
[[ -r /etc/debian_version ]] || { echo 'Requer Debian/Ubuntu/MX.' >&2; exit 1; }
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) echo 'Arquitetura nao suportada.' >&2; exit 1 ;; esac
apt-get update
# O pacote da distribuicao inclui usuario dedicado e integracao systemd/SysVinit.
env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends prometheus-node-exporter curl iproute2
cfg=/etc/default/prometheus-node-exporter
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
printf '%s\n' '# Gerenciado por bootstrap-monitoring.sh' 'ARGS="--web.listen-address=:9100"' >"$tmp"
if ! cmp -s "$tmp" "$cfg"; then
    if [[ -f "$cfg" ]]; then
        backup_dir=$(mktemp -d /var/backups/sucacenter-node-exporter.XXXXXXXX)
        cp -a "$cfg" "$backup_dir/"
        echo "Backup Node Exporter: $backup_dir"
    fi
    install -m 0644 "$tmp" "$cfg"
fi
if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null; then
    systemctl enable prometheus-node-exporter
    systemctl restart prometheus-node-exporter
else
    [[ -x /etc/init.d/prometheus-node-exporter ]] || { echo 'Pacote sem script SysVinit; necessario systemd ativo.' >&2; exit 1; }
    update-rc.d prometheus-node-exporter defaults
    service prometheus-node-exporter restart
fi
for ((i=0; i<30; i++)); do
    if curl --noproxy '*' -fsS --max-time 3 http://127.0.0.1:9100/metrics -o "$tmp" && grep -q '^node_exporter_build_info{' "$tmp"; then
        echo "Node Exporter OK em $(hostname):9100"; exit 0
    fi
    sleep 2
done
echo 'Node Exporter indisponivel; verifique servico e conflito na porta 9100.' >&2
exit 1
NODE

SSH_OPTS=(-p "$SSH_PORT" -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3
    -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPersist=600 -o "ControlPath=$WORK/ssh-%C")
# accept-new registra apenas hosts novos; chaves alteradas continuam bloqueadas.
# PasswordAuthentication permanece interativo; nao usamos sshpass nem gravamos senhas.
while IFS= read -r -u 8 dest; do
    [[ -n "$dest" ]] || continue
    log "Instalando Node Exporter em $dest (SSH/sudo podem solicitar senha)."
    ssh "${SSH_OPTS[@]}" "$dest" true
    CONNECTED+=("$dest")
    REMOTE_DEST=$dest
    REMOTE_TMP=$(ssh "${SSH_OPTS[@]}" "$dest" 'mktemp /tmp/suca-node.XXXXXXXX')
    [[ "$REMOTE_TMP" =~ ^/tmp/suca-node\.[a-zA-Z0-9]+$ ]] || die "mktemp remoto retornou caminho inesperado em $dest."
    scp -P "$SSH_PORT" -o "ControlPath=$WORK/ssh-%C" -o StrictHostKeyChecking=accept-new "$WORK/install-node.sh" "$dest:$REMOTE_TMP"
    remote_uid=$(ssh "${SSH_OPTS[@]}" "$dest" 'id -u')
    if [[ "$remote_uid" == 0 ]]; then
        ssh "${SSH_OPTS[@]}" "$dest" "bash '$REMOTE_TMP'"
    else
        ssh "${SSH_OPTS[@]}" "$dest" 'command -v sudo >/dev/null' || die "sudo ausente em $dest; use root@host ou instale sudo."
        if ssh "${SSH_OPTS[@]}" "$dest" 'sudo -n true' 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" "$dest" "sudo -n -- bash '$REMOTE_TMP'"
        else
            # TTY permite que o proprio sudo leia a senha com eco desativado.
            [[ -r /dev/tty ]] || die "sudo em $dest precisa de senha; execute em um terminal interativo."
            ssh -tt "${SSH_OPTS[@]}" "$dest" "sudo -- bash '$REMOTE_TMP'" </dev/tty
        fi
    fi
    ssh "${SSH_OPTS[@]}" "$dest" "rm -f -- '$REMOTE_TMP'"
    REMOTE_TMP=""
    REMOTE_DEST=""
done 8<"$WORK/connections.txt"
log 'Instalando Node Exporter no master.'
"${SUDO[@]}" bash "$WORK/install-node.sh"

log 'Preparando Docker e Compose no master.'
if ! command -v docker >/dev/null; then
    # Pacotes nativos preservam compatibilidade com o init do MX Linux.
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io
fi
if [[ -d /run/systemd/system ]]; then
    "${SUDO[@]}" systemctl enable --now docker
else
    [[ -x /etc/init.d/docker ]] || die 'Docker sem suporte SysVinit instalado. Use pacote docker.io da distribuicao ou inicialize com systemd.'
    "${SUDO[@]}" update-rc.d docker defaults
    "${SUDO[@]}" service docker start
fi
# Sempre usar o daemon LOCAL; nao alterar um contexto Docker remoto configurado.
dock() { "${SUDO[@]}" env -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host unix:///var/run/docker.sock "$@"; }
for ((i=0; i<30; i++)); do
    if dock info >/dev/null 2>&1; then break; fi
    sleep 2
done
dock info >/dev/null
if ! dock compose version >/dev/null 2>&1; then
    package=""
    for candidate in docker-compose-plugin docker-compose-v2; do
        if apt-cache show "$candidate" >/dev/null 2>&1; then package=$candidate; break; fi
    done
    if [[ -n "$package" ]]; then
        "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"
    else
        log 'Instalando plugin Compose oficial com verificacao SHA256.'
        case "$(uname -m)" in x86_64) compose_arch=x86_64 ;; *) compose_arch=aarch64 ;; esac
        curl -fSL --retry 3 --connect-timeout 15 --max-time 120 https://api.github.com/repos/docker/compose/releases/latest -o "$WORK/compose-release.json"
        compose_tag=$(python3 -c 'import json,sys,re; t=json.load(open(sys.argv[1]))["tag_name"]; assert re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+",t),t; print(t)' "$WORK/compose-release.json")
        asset="docker-compose-linux-$compose_arch"
        url="https://github.com/docker/compose/releases/download/$compose_tag"
        curl -fSL --retry 3 --connect-timeout 15 --max-time 300 "$url/$asset" -o "$WORK/$asset"
        curl -fSL --retry 3 --connect-timeout 15 --max-time 120 "$url/checksums.txt" -o "$WORK/checksums.txt"
        python3 - "$WORK" "$asset" <<'PY'
import sys, pathlib, hashlib
p, name = pathlib.Path(sys.argv[1]), sys.argv[2]
matches = [line.split()[0] for line in (p/'checksums.txt').read_text().splitlines()
           if len(line.split()) == 2 and line.split()[1].lstrip('*') == name]
if len(matches) != 1 or hashlib.sha256((p/name).read_bytes()).hexdigest() != matches[0]:
    raise SystemExit('Checksum Compose invalido/ausente.')
PY
        "${SUDO[@]}" install -D -m 0755 "$WORK/$asset" /usr/local/lib/docker/cli-plugins/docker-compose
    fi
fi
dock compose version
port_busy() {
    [[ -n "$(ss -H -ltn "sport = :$1")" ]] || dock ps --format '{{.Ports}}' | grep -q -- ":$1->"
}
if [[ -z "$GRAFANA_PORT" ]] && "${SUDO[@]}" test -s "$BASE/grafana-port.txt"; then
    GRAFANA_PORT=$("${SUDO[@]}" cat "$BASE/grafana-port.txt")
fi
if [[ -z "$GRAFANA_PORT" ]]; then
    GRAFANA_PORT=3000
    owned=$(dock ps -q --filter label=com.docker.compose.project=sucacenter-monitoring --filter label=com.docker.compose.service=grafana)
    if [[ -z "$owned" ]] && port_busy 3000; then
        GRAFANA_PORT=3001
        log 'Porta 3000 ocupada; Grafana usara 3001 (Gitea preservado).'
    fi
fi
[[ "$GRAFANA_PORT" =~ ^[0-9]{4,5}$ ]] && ((10#$GRAFANA_PORT >= 1024 && 10#$GRAFANA_PORT <= 65535)) || die 'GRAFANA_PORT deve estar entre 1024 e 65535.'
GRAFANA_PORT=$((10#$GRAFANA_PORT))
[[ "$GRAFANA_PORT" != 9090 && "$GRAFANA_PORT" != 9100 ]] || die 'GRAFANA_PORT conflita com Prometheus/Node Exporter.'
printf '%s\n' "$GRAFANA_PORT" >"$WORK/grafana-port.txt"
for port in 9090 "$GRAFANA_PORT"; do
    svc=prometheus
    [[ "$port" != "$GRAFANA_PORT" ]] || svc=grafana
    if port_busy "$port"; then
        owned=$(dock ps -q --filter label=com.docker.compose.project=sucacenter-monitoring --filter "label=com.docker.compose.service=$svc")
        [[ -n "$owned" ]] || die "Porta $port ja esta ocupada por outro servico. Libere-a antes de executar novamente."
    fi
done

log 'Preparando imagens (digests persistidos para repetibilidade).'
if "${SUDO[@]}" test -f "$BASE/images.json"; then
    "${SUDO[@]}" cat "$BASE/images.json" >"$WORK/images.json"
else
    dock pull "$PROMETHEUS_IMAGE"
    dock pull "$GRAFANA_IMAGE"
    dock image inspect "$PROMETHEUS_IMAGE" >"$WORK/prom-image.json"
    dock image inspect "$GRAFANA_IMAGE" >"$WORK/graf-image.json"
    python3 - "$WORK" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
images={k: json.loads((p/f).read_text())[0]['RepoDigests'][0]
        for k,f in [('prometheus','prom-image.json'),('grafana','graf-image.json')]}
(p/'images.json').write_text(json.dumps(images, indent=2)+'\n')
PY
fi
log 'Gerando Prometheus, datasource e dashboard OnePage.'
python3 - "$WORK" "$GRAFANA_BIND" "$GRAFANA_PORT" <<'PY'
import json, pathlib, sys, re
p=pathlib.Path(sys.argv[1]); bind=sys.argv[2]; port=sys.argv[3]
images=json.loads((p/'images.json').read_text())
for image in images.values():
    if not re.fullmatch(r'[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}', image):
        raise SystemExit('images.json invalido; requer imagens fixadas por SHA256.')
nodes=[dict(host='127.0.0.1', node='master')]+json.loads((p/'nodes.json').read_text())
config={'global':{'scrape_interval':'15s','evaluation_interval':'15s'},
        'scrape_configs':[{'job_name':'nodes','scrape_timeout':'10s','static_configs':[
            {'targets':[n['host']+':9100'], 'labels':{'node':n['node']}} for n in nodes]}]}
# JSON e um subconjunto de YAML aceito pelo Prometheus e pelo Docker Compose.
(p/'prometheus.yml').write_text(json.dumps(config,indent=2)+'\n')
compose={'name':'sucacenter-monitoring','services':{
 'prometheus':{'image':images['prometheus'],'restart':'unless-stopped','network_mode':'host',
   'command':['--config.file=/etc/prometheus/prometheus.yml','--storage.tsdb.path=/prometheus',
              '--storage.tsdb.retention.time=15d','--web.listen-address=127.0.0.1:9090'],
   'volumes':['./prometheus.yml:/etc/prometheus/prometheus.yml:ro','prometheus-data:/prometheus'],
   'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'3'}}},
 'grafana':{'image':images['grafana'],'restart':'unless-stopped','network_mode':'host',
   'environment':{'GF_SERVER_HTTP_ADDR':bind,'GF_SERVER_HTTP_PORT':port,
     'GF_SECURITY_ADMIN_USER':'admin','GF_SECURITY_ADMIN_PASSWORD__FILE':'/run/secrets/grafana_admin_password',
     'GF_USERS_ALLOW_SIGN_UP':'false','GF_AUTH_ANONYMOUS_ENABLED':'false',
     'GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH':'/var/lib/grafana/dashboards/onepage.json'},
   'secrets':['grafana_admin_password'],
   'volumes':['grafana-data:/var/lib/grafana','./provisioning:/etc/grafana/provisioning:ro',
              './dashboards:/var/lib/grafana/dashboards:ro'],
   'logging':{'driver':'json-file','options':{'max-size':'10m','max-file':'3'}}}},
 'volumes':{'prometheus-data':{},'grafana-data':{}},
 'secrets':{'grafana_admin_password':{'file':'./secrets/grafana_admin_password'}}}
(p/'docker-compose.yml').write_text(json.dumps(compose,indent=2)+'\n')
(p/'datasource.yml').write_text('''apiVersion: 1
datasources:
  - name: Prometheus
    uid: sucacenter-prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
''')
(p/'provider.yml').write_text('''apiVersion: 1
providers:
  - name: SucaCenter
    orgId: 1
    folder: SucaCenter
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
''')
ds={'type':'prometheus','uid':'sucacenter-prometheus'}
def panel(pid,title,expr,x,y,w,unit='percent',kind='gauge'):
    return {'id':pid,'title':title,'type':kind,'datasource':ds,
      'gridPos':{'x':x,'y':y,'w':w,'h':5},
      'targets':[{'refId':'A','expr':expr,'instant':True,'legendFormat':'{{node}}'}],
      'fieldConfig':{'defaults':{'unit':unit,'min':0,
          **({'max':100} if unit=='percent' else {}),
          'noValue':'Sem dados','thresholds':{'mode':'absolute','steps':[
          {'color':'green','value':None},{'color':'yellow','value':80},{'color':'red','value':90}]}},'overrides':[]},
      'options':{'reduceOptions':{'calcs':['lastNotNull'],'fields':'','values':False},
                 'orientation':'horizontal','colorMode':'value','textMode':'auto'}}
panels=[]
for index,n in enumerate(nodes):
    # JSON quoting produces a valid escaped PromQL string for the validated node label.
    sel='job="nodes",node='+json.dumps(n['node'])
    y=index*6
    status=panel(index*10+1,n['node']+' | UP / DOWN','up{'+sel+'}',0,y,3,'none','stat')
    status['fieldConfig']['defaults'].update({'mappings':[{'type':'value','options':{
        '0':{'text':'DOWN','color':'red'},'1':{'text':'UP','color':'green'}}}],
        'thresholds':{'mode':'absolute','steps':[{'color':'red','value':None},{'color':'green','value':1}]}})
    panels.append(status)
    # As metricas de um no DOWN ficam vazias em vez de exibir valores antigos.
    up=' and on(node) (up{'+sel+'} == 1)'
    cpu='100 * (1 - avg by(node) (rate(node_cpu_seconds_total{'+sel+',mode="idle"}[2m])))'
    ram='100 * (1 - node_memory_MemAvailable_bytes{'+sel+'} / node_memory_MemTotal_bytes{'+sel+'})'
    fs=sel+',fstype!~"tmpfs|devtmpfs|overlay|squashfs|ramfs|nsfs|autofs",mountpoint!~"/run.*|/var/lib/docker.*|/var/lib/containers.*"'
    disk='max by(node) (100 * (1 - node_filesystem_avail_bytes{'+fs+'} / (node_filesystem_size_bytes{'+fs+'} > 0)))'
    panels.extend([panel(index*10+2,'CPU | '+n['node'],'('+cpu+')'+up,3,y,4),
                   panel(index*10+3,'RAM | '+n['node'],'('+ram+')'+up,7,y,4),
                   panel(index*10+4,'Disco mais cheio | '+n['node'],'('+disk+')'+up,11,y,4)])
    for offset,(direction,metric,x,w) in enumerate([('RX','receive',15,4),('TX','transmit',19,5)]):
        expr='sum by(node) (rate(node_network_'+metric+'_bytes_total{'+sel+',device!~"lo|veth.*|docker.*|br-.*"}[2m]))'
        net=panel(index*10+5+offset,direction+' | '+n['node'],'('+expr+')'+up,x,y,w,'Bps','stat')
        net['fieldConfig']['defaults']['thresholds']['steps']=[{'color':'blue','value':None}]
        panels.append(net)
dashboard={'uid':'sucacenter-onepage','title':'SucaCenter | Cluster OnePage','tags':['sucacenter','linux'],
  'timezone':'browser','schemaVersion':39,'version':1,'refresh':'15s','editable':False,
  'time':{'from':'now-30m','to':'now'},'panels':panels,'templating':{'list':[]},
  'description':'Uma linha por no. Disco: maior uso entre filesystems reais. Rede: soma RX/TX das interfaces, excluindo loopback e bridges Docker comuns; bonds podem duplicar contagem. CPU/rede requerem duas coletas. DOWN significa falha de coleta, nao necessariamente maquina desligada.'}
(p/'onepage.json').write_text(json.dumps(dashboard,ensure_ascii=False,indent=2)+'\n')
PY

# Valida antes de substituir as configuracoes ativas.
prom_image=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["prometheus"])' "$WORK/images.json")
graf_image=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["grafana"])' "$WORK/images.json")
dock pull "$prom_image"
dock pull "$graf_image"
# Arquivo legivel pelo usuario sem privilegios do container; diretorio temporario continua 0700.
chmod 0644 "$WORK/prometheus.yml"
dock run --rm --network none --entrypoint /bin/promtool -v "$WORK/prometheus.yml:/etc/prometheus/prometheus.yml:ro" "$prom_image" check config /etc/prometheus/prometheus.yml
# Consulta o parser PromQL da mesma versao do Prometheus na validacao final.

log 'Salvando backup e instalando configuracoes.'
"${SUDO[@]}" bash -s -- "$BASE" "$WORK" <<'INSTALL'
set -Eeuo pipefail
base=$1; work=$2
backup=""
for rel in prometheus.yml docker-compose.yml provisioning dashboards hosts.txt images.json grafana-port.txt; do
    if [[ -e "$base/$rel" ]]; then
        if [[ -z "$backup" ]]; then
            install -d -m 0700 "$base/backups"
            backup=$(mktemp -d "$base/backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
        fi
        cp -a "$base/$rel" "$backup/"
    fi
done
[[ -z "$backup" ]] || echo "Backup: $backup"
install -d -m 0755 "$base/provisioning" "$base/provisioning/datasources" "$base/provisioning/dashboards" "$base/dashboards"
install -d -m 0700 "$base/secrets"
for name in prometheus.yml docker-compose.yml hosts.txt images.json grafana-port.txt; do
    install -m 0644 "$work/$name" "$base/$name.new"
    mv -f "$base/$name.new" "$base/$name"
done
install -m 0644 "$work/datasource.yml" "$base/provisioning/datasources/sucacenter.yml"
install -m 0644 "$work/provider.yml" "$base/provisioning/dashboards/sucacenter.yml"
install -m 0644 "$work/onepage.json" "$base/dashboards/onepage.json"
if [[ ! -s "$base/secrets/grafana_admin_password" ]]; then
    python3 - "$base/secrets/grafana_admin_password" <<'PY'
import secrets,sys,os
fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o400)
with os.fdopen(fd,'w') as f: f.write(secrets.token_urlsafe(24))
PY
fi
# Compose local usa bind mount para secrets. Arquivo deve ser legivel pelo UID do Grafana;
# diretorio pai 0700 impede acesso por outros usuarios do host. Nao e incluido em backups.
chmod 0444 "$base/secrets/grafana_admin_password"
INSTALL
compose() { dock compose --project-name sucacenter-monitoring --file "$BASE/docker-compose.yml" "$@"; }
compose config --quiet
log 'Subindo Prometheus e Grafana.'
# Recriar atualiza bind mounts mesmo quando arquivos foram substituidos atomicamente.
# Ha uma breve interrupcao em reexecucoes; volumes de dados sao preservados.
compose up -d --force-recreate

log "Validando endpoints 9100, 9090, $GRAFANA_PORT e coleta de TODOS os nos."
graf_check=$GRAFANA_BIND
[[ "$graf_check" != 0.0.0.0 ]] || graf_check=127.0.0.1
python3 - "$WORK/nodes.json" "$graf_check" "$WORK/onepage.json" "$GRAFANA_PORT" <<'PY'
import json,sys,time,urllib.request,urllib.parse
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def get(url):
    with opener.open(url,timeout=5) as r: return r.read().decode()
nodes=[dict(host='127.0.0.1')]+json.load(open(sys.argv[1]))
checks=[('Node Exporter '+n['host'], 'http://'+n['host']+':9100/metrics','node_exporter_build_info') for n in nodes]
checks += [('Prometheus','http://127.0.0.1:9090/-/ready',None),
           ('Grafana','http://'+sys.argv[2]+':'+sys.argv[4]+'/api/health','"ok"')]
errors={}
deadline=time.monotonic()+180
pending=checks[:]
while pending and time.monotonic()<deadline:
    for check in pending[:]:
        name,url,marker=check
        try:
            body=get(url)
            if marker and marker not in body: raise ValueError('resposta inesperada')
            print('OK: '+name,flush=True); pending.remove(check)
        except Exception as e: errors[name]=str(e)
    if pending: time.sleep(3)
if pending:
    raise SystemExit('Endpoints indisponiveis: '+str({c[0]:errors[c[0]] for c in pending})+
                     '. Verifique firewall, resolucao DNS, portas ocupadas e logs dos servicos.')
deadline=time.monotonic()+90
while True:
    targets=json.loads(get('http://127.0.0.1:9090/api/v1/targets'))['data']['activeTargets']
    targets=[t for t in targets if t['labels'].get('job')=='nodes']
    bad=[t for t in targets if t['health']!='up']
    if len(targets)==len(nodes) and not bad: break
    if time.monotonic()>deadline:
        raise SystemExit('Falha de coleta Prometheus: '+str([(t['scrapeUrl'],t.get('lastError')) for t in bad])+
                         f' (targets encontrados: {len(targets)}/{len(nodes)}).')
    time.sleep(3)
print(f'OK: Prometheus coletando {len(targets)} nos.',flush=True)
dashboard=json.load(open(sys.argv[3]))
for panel in dashboard['panels']:
    for target in panel['targets']:
        result=json.loads(get('http://127.0.0.1:9090/api/v1/query?'+urllib.parse.urlencode({'query':target['expr']})))
        if result.get('status')!='success': raise SystemExit('Consulta invalida: '+panel['title'])
print('OK: todas as consultas do dashboard aceitas pelo Prometheus.',flush=True)
PY

display_ip=$GRAFANA_BIND
if [[ "$display_ip" == 0.0.0.0 ]]; then
    display_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1);exit}}') || true
    display_ip=${display_ip:-$(hostname -I | awk '{print $1}')}
    display_ip=${display_ip:-127.0.0.1}
fi
log 'Instalacao validada!'
printf 'Dashboard: http://%s:%s/d/sucacenter-onepage\nUsuario: admin\n' "$display_ip" "$GRAFANA_PORT"
if [[ -w /dev/tty ]]; then
    printf '\nSenha INICIAL do Grafana (se alterada pela interface, use a senha atual): ' >/dev/tty
    "${SUDO[@]}" cat "$BASE/secrets/grafana_admin_password" >/dev/tty
    printf '\n' >/dev/tty
else
    printf 'Senha inicial: consulte como root %s/secrets/grafana_admin_password\n' "$BASE"
fi
printf '\nConfiguracoes: %s\nPrometheus local: http://127.0.0.1:9090\n' "$BASE"
printf 'CPU/rede podem levar cerca de 30 segundos para aparecer. DOWN indica falha de coleta.\n'
printf 'Para mudar os nos: HOSTS="usuario@host1 usuario@host2" bash bootstrap-monitoring.sh\n'
printf 'Restrinja 9100 ao master e %s a sua rede/VPN. O script nao modifica o firewall.\n' "$GRAFANA_PORT"
