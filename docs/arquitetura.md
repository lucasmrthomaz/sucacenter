# Arquitetura

O master organiza trabalho; não transforma os computadores em uma máquina com
RAM compartilhada.

- GNU Parallel: comandos independentes por SSH.
- distcc: unidades C/C++; pré-processamento/linker normalmente no master.
- ccache: evita repetir compilações idênticas.
- Rust/Go/Zig/Node/.NET/Java: wrappers locais; distribua projetos/testes/jobs.
- Docker Engine: containers; Compose: aplicação em um host.
- Swarm: serviços/réplicas em hosts; um manager e um worker não oferecem alta
  disponibilidade da gestão. Dois managers também não toleram perder um por quorum.
- K3s/Kubernetes: alternativas, não dependências deste projeto.

## Laboratório de origem

| Papel | Máquina | IP |
|---|---|---|
| master/manager | Vostro Core 2 Duo E8500, 2 núcleos | 192.168.1.110 |
| worker | Samsung i5-2450M, 2 núcleos/4 threads | 192.168.1.103 |

KVM foi detectado no Vostro, mas Docker Engine nativo não depende de KVM.
Containers não emulam instruções ausentes: compatibilidade depende dos programas.
RAM/disco precisam ser medidos para dimensionar serviços.

## Diretórios e dados

~/cluster/{logs,jobs,shared-files,workloads,config,archives,output,app,scripts}
e ~/bin. Código e configuração não substituem backup de dados e volumes Docker.

nodes é preservado ao reinstalar. sync-push usa master como origem, sem --delete;
versões sobrescritas vão para backups. sync-pull guarda os workers separados.
Não é sincronização bidirecional nem backup com retenção automática. Nunca
sincronize bancos/volumes ativos com rsync.

Referências: [Swarm](https://docs.docker.com/engine/swarm/),
[quorum](https://docs.docker.com/engine/swarm/admin_guide/),
[distcc](https://www.distcc.org/man/distcc_1.html),
[K3s](https://docs.k3s.io/installation/requirements).
