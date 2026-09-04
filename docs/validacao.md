# Validação

## Evidências do laboratório original

O usuário confirmou SSH para o Samsung, GCC 13.3.0 idêntico, compilação remota
distcc sem fallback e Swarm com Leader/worker Ready/Active, Docker 29.1.3.
Carga SHA-256 de 60s: Vostro 459,6 MiB/s; Samsung 506,7 MiB/s.

São evidências históricas, não garantia em outro sistema. Não há resultado
confirmado do teste completo de aplicação overlay nem benchmark de projeto C++
distribuído na conversa de origem.

## Esta versão

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
