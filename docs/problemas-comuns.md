# Problemas comuns

## sudo: usuário cluster não autorizado

A conta não recebeu autorização. Repetir não concede permissão. Execute as etapas
de sistema por uma conta administradora. Não execute todo o setup como root.

## Docker active, mas permission denied

    command -v docker
    systemctl is-active docker
    id
    ls -l /var/run/docker.sock
    docker --host unix:///var/run/docker.sock info

Se socket root:docker e usuário sem grupo docker, um administrador pode autorizar
sudo usermod -aG docker cluster. Saia e reconecte. Grupo docker equivale a root;
não torne o socket acessível a todos.

## Swarm Ready não prova aplicação funcionando

Execute test swarm: HTTP entre containers de hosts diferentes, HTTP nos IPs e
escala 2 → 4. Para Pending/Rejected: docker service ps --no-trunc ID.
Verifique registry, firewall, disco e compatibilidade da imagem com CPU antiga.

O teste requer dois nós Ready/Active e porta 18080 livre. Cria novos nomes sem
substituir serviços. Outra porta:
SUCACENTER_TEST_PORT=18081 bash sucacenter.sh test swarm.

## SSH

Autorize chave, carregue passphrase no ssh-agent e confira fingerprint.
BatchMode não aceita senha interativa. Não desabilite StrictHostKeyChecking nem
apague known_hosts para esconder um erro.

## distcc sem porta 3632

Verifique STARTDISTCC, LISTENER, ALLOWEDNETS em /etc/default/distcc no worker.
GCC deve ser compatível. test distcc desativa fallback para revelar falhas remotas.

## Etapa interrompida / outro Swarm

Veja ~/cluster/config/state e ~/cluster/logs. Repita setup ou step NOME.
Não há rollback global: recursos criados permanecem. Nós de outro Swarm não são
migrados automaticamente. Não use --force-new-cluster como correção genérica.
