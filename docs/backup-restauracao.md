# Backup e restauração

GitHub guarda código e documentação. Não guarda os dados nem estado Docker/Swarm.
Mantenha backups fora das duas máquinas.

Guarde configurações nodes/settings.env separadamente, shared-files/workloads,
volumes e dumps consistentes dos bancos, arquivos Compose/stacks, versões/digests
das imagens e credenciais em gerenciador de segredos. Nunca em commits.

Para arquivos comuns parados: cluster-archive e cluster-checksum. Copie o resultado
para armazenamento separado e faça uma restauração de teste. A replicação de
shared-files não protege contra corrupção/exclusão/perda dos dois discos.
Não arquive bancos em uso sem garantir consistência.

## Reconstruir

1. Instale Linux, pré-requisitos, contas e IPs.
2. Recupere ZIP/repositório privado e leia instalação.
3. Autorize SSH e configure nodes/settings.env.
4. Execute setup e testes distcc/Swarm.
5. Restaure dados, permissões necessárias e aplicações.
6. Verifique acesso e backups.

Para restaurar o mesmo Swarm, faça backup consistente do estado do manager segundo
a documentação. Para recriar, reinstale infraestrutura e restaure aplicações/dados.
O instalador não restaura volumes nem implanta suas stacks antigas automaticamente.

[Backup de Swarm](https://docs.docker.com/engine/swarm/admin_guide/#back-up-the-swarm).
