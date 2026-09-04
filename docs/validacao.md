# Validação

## Replicacao v1.2.0

Em 2026-09-04 passaram 20 testes unitarios em Linux, sintaxe Bash e syntax-check
Ansible de site.yml, replication.yml e replication-status.yml (ansible-core
2.21.3). Um teste isolado com duas instancias reais de Syncthing 1.29.5 tambem
confirmou copia, atualizacao, exclusao com historico, reconfiguracao idempotente
e deteccao de alteracoes locais na replica receiveonly.

O teste usa loopback e pastas temporarias locais, sem SSH, sudo ou systemd.
A instalacao nos dois computadores do laboratorio ainda deve ser executada e
verificada pelo usuario. CI remoto pode continuar bloqueado pela conta GitHub;
nao confunda esse estado com os testes locais descritos acima.

## Evidências do laboratório original

O usuário confirmou SSH para o Samsung, GCC 13.3.0 idêntico, compilação remota
distcc sem fallback e Swarm com Leader/worker Ready/Active, Docker 29.1.3.
Carga SHA-256 de 60s: Vostro 459,6 MiB/s; Samsung 506,7 MiB/s.

São evidências históricas, não garantia em outro sistema. Não há resultado
confirmado do teste completo de aplicação overlay nem benchmark de projeto C++
distribuído na conversa de origem.

## Esta versão

A versao unificada 1.1.0 adiciona testes locais de coleta, reexecucao com
backup, IPs esperados e reutilizacao de Docker pelo Gitea. A sintaxe Bash e
testada; syntax-check Ansible e conectividade real devem ser executados no
Linux com `bash sucacenter.sh services validate`. Nenhum servico foi aplicado
ao cluster durante esta mesclagem. Os 13 testes locais passaram antes da
publicacao. O resultado do CI remoto deve ser consultado na aba Actions;
o historico da v1.0.0 teve bloqueio de execucao por cobranca da conta.

Testes verificam sintaxe, preservação de nodes, instalação local repetida,
propagação de falhas, checksums, roundtrip de arquivo e rejeição de traversal/links.
Docker/Swarm derivam dos helpers usados no laboratório, mas o pacote refatorado
não foi reinstalado automaticamente nas máquinas.

CI não usa sudo/apt nem acessa hosts. Verde no CI não comprova rede/firewall:

    bash sucacenter.sh test distcc
    bash sucacenter.sh test benchmark
    bash sucacenter.sh test swarm

Swarm live cria recursos novos, publica porta 18080, mantém recursos e imprime
remoção por IDs. Limites por réplica: 64 MiB e 0,25 CPU. Baixar imagens exige rede.
