# Histórico

## Não lançado

- Instalador autônomo bootstrap-monitoring.sh para Prometheus, Grafana e Node Exporter.
- Dashboard OnePage, credencial gerada, backups de configuração e dados persistentes.
- Porta alternativa automática para coexistir com o Gitea e documentação de operação.
- Script incluído no pacote distribuível e testes de geração sem acesso ao cluster.

## 1.3.0

- Portainer CE LTS como stack opcional do Docker Swarm.
- Servidor fixado ao manager e Agent global nos nos Linux.
- Somente HTTPS 9443 publicada; portas internas e Edge nao expostas.
- Comandos portainer validate|setup|status, espera de convergencia e protecoes.
- Volume persistente preservado em atualizacoes e documentacao de seguranca.

## 1.2.0

- Replicacao automatica e unidirecional do shared com Syncthing.
- Historico de ate 20 versoes por arquivo / 30 dias nas replicas, em discos locais.
- Comandos replication validate|setup|status e servico systemd independente.
- Preserva Samba/NFS; nao altera Docker, Gitea, Slurm ou arquivos existentes.
- Recusa destino NFS, links, pastas nao gerenciadas e mudanca de disco.
- GUI somente loopback, pareamento por IDs e trafego apenas entre IPs LAN.
- Testes de idempotencia, protecao de caminhos e sincronizacao real isolada.

## 1.1.0

- Integra os cinco playbooks e inventory da tarefa Ansible.
- Adiciona services prepare|validate|run e setup --services.
- Mantem IPs 192.168.1.110 e 192.168.1.103, usuario SSH cluster e backups.
- Gitea reutiliza Docker/Compose da base, com original arquivado.
- Inclui camada Ansible no ZIP, instalador unico e copia operacional.
- NFS e sincronizacao local continuam com caminhos e papeis distintos.

## 1.0.0

- Etapas separadas: preflight, workspace, dependências, SSH, distcc, Docker e Swarm.
- Estado/log por etapa; falhas não são marcadas como sucesso.
- ZIP e instalador autocontido gerados do mesmo código.
- distcc restrito ao master; ccache com CCACHE_PREFIX correto.
- Descompactação, resize/optimize e mídia substituem aliases incorretos do protótipo.
- Verificação de integridade e extração que rejeita links/caminhos externos.
- Argumentos preservados, falhas de build/test propagadas e carga limitada.
- Limpeza recursiva de jobs/saídas removida.
- Documentação de permissões, reconstrução, limites e backup separado.
