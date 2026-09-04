# Comandos

Abra nova sessão para carregar ~/bin. Escopo local, exceto onde explicitamente
há iteração por nodes.

## Arquivos

    cluster-sync-push
    cluster-sync-pull
    cluster-checksum ~/cluster/shared-files ~/cluster/logs/checksum-01.json
    cluster-verify ~/cluster/shared-files ~/cluster/logs/checksum-01.json
    cluster-archive ~/cluster/shared-files ~/cluster/archives/backup-01.tar.gz
    cluster-decompress ~/cluster/archives/backup-01.tar.gz ~/cluster/restaurado-01

Saídas não são sobrescritas. Extração exige destino novo e rejeita links/caminhos
externos/arquivos especiais. Usa permissões padrão da conta, não restaura
permissões de sistema. Manifestos JSON SHA-256 não são os do protótipo antigo.

    cluster-image-convert fotos saida-png png
    cluster-image-resize fotos saida-1280 1280
    cluster-image-optimize fotos saida-jpg 85
    cluster-video videos saida-video
    cluster-audio musicas saida-audio

Destino deve ser novo. Processamento sequencial conserva RAM e mantém originais.
Resize/optimize exportam JPEG sem transparência. Optimize pode perder qualidade
e metadados. Estrutura relativa e extensão original no nome evitam colisões.
Falhas preservam saídas parciais; escolha outro destino para repetir.

## Builds

    JOBS=6 cluster-build-c ~/projeto
    cluster-build rust ~/projeto
    cluster-build-go ~/projeto
    cluster-test ~/projeto
    cluster-lint ~/projeto

C/C++ requer Makefile. ccache usa CCACHE_PREFIX=distcc. Não injeta -march=native
ou LTO; use flags compatíveis com ambos os processadores. Para CMake use
CMAKE_C_COMPILER_LAUNCHER=ccache e equivalente C++, com CCACHE_PREFIX=distcc.

Toolchains opcionais não são baixadas por scripts de terceiros. Instale versões
adequadas ao projeto; Zig e .NET podem faltar no apt padrão. cluster-install
PACOTE exige autorização. Gradle/npm/Maven executam código: use projetos confiáveis.
Lint Java usa verify (Maven) ou check (Gradle) configurados pelo projeto.

## Jobs/manutenção

    printf '%s\n' tarefa1 tarefa2 | cluster-run echo '{}'
    cluster-exec uname -a
    cluster-burn 60
    cluster-logs 100
    cluster-clean

cluster-run usa GNU Parallel; cluster-exec preserva argumentos e propaga falhas.
Para expansão remota explícita use cluster-exec bash -c '...'.
burn é carga SHA-256 local limitada, não benchmark de rede/distcc.
clean aplica a limpeza do ccache, sem apagar jobs/saídas. update só atualiza índices
apt, sem upgrade global. reboot/shutdown são locais e exigem --yes.
jobs/queue é somente estrutura inicial, sem daemon.

Docker: cluster-docker help; cluster-docker-status --all; cluster-compose up -d.
Swarm: cluster-swarm setup; cluster-swarm status.

## Portainer

    bash sucacenter.sh portainer validate
    bash sucacenter.sh portainer setup
    bash sucacenter.sh portainer status

Execute no worker01. Acesse `https://192.168.1.110:9443` somente pela LAN ou
por VPN privada. Veja [Portainer](portainer.md).
