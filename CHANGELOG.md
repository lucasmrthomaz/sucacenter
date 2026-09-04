# Histórico

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
