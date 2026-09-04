# Histórico

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
