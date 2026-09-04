#!/usr/bin/env bash
# Teste funcional do Swarm SucaCenter. Execute no manager como cluster.
# Cria somente serviço/rede novos; não altera aplicações existentes.
set -euo pipefail
command -v python3 >/dev/null || { echo "Falta python3."; exit 1; }
exec python3 - <<'PY'
import collections
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

env = os.environ.copy()
env.pop("DOCKER_HOST", None)
env.pop("DOCKER_CONTEXT", None)
docker = ["docker", "--host", "unix:///var/run/docker.sock"]
service_id = network_id = None
root = None

def run(*args):
    p = subprocess.run(docker + list(args), env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip())
    return p.stdout.strip()

def inspect(*args):
    return json.loads(run(*args))

def tasks():
    ids = run("service", "ps", "--no-trunc", "-q",
              "--filter", "desired-state=running", service_id).split()
    return inspect("inspect", *ids) if ids else []

def wait_for(per_node):
    goal = per_node * 2
    deadline = time.monotonic() + 300
    next_report = 0
    while time.monotonic() < deadline:
        current = tasks()
        running = [t for t in current if t["Status"]["State"] == "running"]
        counts = collections.Counter(t["NodeID"] for t in running)
        if len(current) == goal and counts == {node: per_node for node in node_ids}:
            return running
        if time.monotonic() >= next_report:
            print(f"  {len(running)}/{goal} rodando; distribuição: {dict(counts)}",
                  flush=True)
            next_report = time.monotonic() + 10
        time.sleep(2)
    raise RuntimeError("Prazo de 5 minutos esgotado ao aguardar as réplicas.")

def http(url):
    # Ignora proxies do ambiente: os endereços são os próprios nós da LAN.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=5) as response:
        return response.read(4096).decode().strip()

def retry(fn, expected, description):
    deadline = time.monotonic() + 45
    last = ""
    while time.monotonic() < deadline:
        try:
            last = fn()
            if expected(last):
                print(f"OK {description}: {last}", flush=True)
                return
        except Exception as error:
            last = str(error)
        time.sleep(2)
    raise RuntimeError(f"{description}: {last}")

try:
    if not shutil.which("docker"):
        raise RuntimeError("Docker não está instalado.")
    info = inspect("info", "--format", "{{json .}}")
    if not info["Swarm"].get("ControlAvailable"):
        raise RuntimeError("Execute no manager do Swarm.")
    me = info["Swarm"]["NodeID"]
    ids = run("node", "ls", "-q").split()
    nodes = inspect("node", "inspect", *ids)
    nodes = [n for n in nodes if n["Status"]["State"] == "ready"
             and n["Spec"]["Availability"] == "active"]
    if len(nodes) != 2 or me not in [n["ID"] for n in nodes]:
        raise RuntimeError("Este teste requer exatamente dois nós Ready/Active, incluindo o manager.")
    node_ids = {n["ID"] for n in nodes}
    port = int(os.environ.get("SUCACENTER_TEST_PORT", "18080"))
    if not 1024 <= port <= 65535:
        raise RuntimeError("SUCACENTER_TEST_PORT deve estar entre 1024 e 65535.")
    base = Path.home() / "cluster" / "logs"
    base.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="swarm-test-", dir=base))
    name = root.name
    network_name = name + "-net"
    label = "sucacenter.test=" + name
    print(f"Logs: {root}\nPublicação: porta TCP {port} nos nós do Swarm.", flush=True)
    network_id = run("network", "create", "--driver", "overlay",
                     "--label", label, network_name)

    print("1/4: criando duas réplicas, no máximo uma por máquina...", flush=True)
    service_id = run(
        "service", "create", "--detach=true", "--name", name,
        "--label", label, "--network", network_name,
        "--replicas", "2", "--replicas-max-per-node", "1",
        "--limit-memory", "64m", "--limit-cpu", "0.25",
        "--env", "NODE={{.Node.Hostname}}",
        "--publish", f"published={port},target=8080,mode=ingress",
        "--log-driver", "json-file", "--log-opt", "max-size=1m",
        "--log-opt", "max-file=2",
        "busybox:1.37.0-musl", "sh", "-c",
        'mkdir -p /www; printf "SucaCenter | node=%s | container=%s\\n" '
        '"$NODE" "$(hostname)" > /www/index.html; '
        'exec httpd -f -p 8080 -h /www'
    )
    first = wait_for(1)
    (root / "tasks-2.json").write_text(json.dumps(first, indent=2))
    print("OK: uma réplica em cada máquina.", flush=True)

    print("2/4: verificando HTTP direto entre containers de máquinas diferentes...", flush=True)
    local = next(t for t in first if t["NodeID"] == me)
    remote = next(t for t in first if t["NodeID"] != me)
    cid = local["Status"]["ContainerStatus"]["ContainerID"]
    attachment = next(a for a in remote["NetworksAttachments"]
                      if a["Network"]["ID"] == network_id)
    remote_ip = attachment["Addresses"][0].split("/")[0]
    remote_name = next(n["Description"]["Hostname"] for n in nodes
                       if n["ID"] == remote["NodeID"])
    retry(
        lambda: run("exec", cid, "wget", "-T", "5", "-qO-", f"http://{remote_ip}:8080/"),
        lambda body: f"node={remote_name} |" in body,
        "overlay manager → worker"
    )

    print("3/4: verificando acesso HTTP pelos dois IPs publicados...", flush=True)
    for node in nodes:
        url = f"http://{node['Status']['Addr']}:{port}/"
        retry(lambda u=url: http(u), lambda body: body.startswith("SucaCenter |"),
              url)

    print("4/4: aumentando para quatro réplicas, no máximo duas por máquina...", flush=True)
    run("service", "update", "--detach=true", "--replicas-max-per-node", "2",
        "--replicas", "4", service_id)
    final = wait_for(2)
    (root / "tasks-4.json").write_text(json.dumps(final, indent=2))
    for node in nodes:
        url = f"http://{node['Status']['Addr']}:{port}/"
        retry(lambda u=url: http(u), lambda body: body.startswith("SucaCenter |"),
              "HTTP após escala " + url)
    print(run("service", "ps", "--no-trunc", service_id), flush=True)
    print("\nSUCESSO: overlay entre máquinas, HTTP nos dois IPs e escala 2 → 4.")
    print("Distribuição confirmada: duas réplicas em cada máquina.")
    print("Serviço mantido disponível (teste funcional, não benchmark de desempenho).")
    for node in nodes:
        print(f"Acesse: http://{node['Status']['Addr']}:{port}/")
except Exception as error:
    print(f"\nFALHOU: {error}", file=sys.stderr)
    if service_id:
        try:
            details = run("service", "ps", "--no-trunc", service_id)
            print(details, file=sys.stderr)
            (root / "diagnostico.txt").write_text(str(error) + "\n" + details)
        except Exception:
            pass
    sys.exit(1)
finally:
    if root:
        (root / "recursos.json").write_text(json.dumps({
            "service_id": service_id, "network_id": network_id
        }, indent=2))
    if service_id:
        print(f"\nPara remover somente este serviço de teste:\ndocker service rm {service_id}")
    if network_id:
        print("Depois que as tarefas terminarem, remova a rede de teste:")
        print(f"docker network rm {network_id}")
PY
