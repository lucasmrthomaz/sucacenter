# Instalação por etapas

## 0. Linux, contas e IPs

Use Linux Mint/Ubuntu/Debian com systemd e Python 3.9+. Em cada máquina, uma conta
administradora prepara os pré-requisitos ausentes:

    sudo apt-get update
    sudo apt-get install -y openssh-server python3
    sudo systemctl enable --now ssh

Reserve IPs no roteador ou configure endereços estáticos. O instalador não altera
endereços de rede, não cria contas nem muda sudoers. Ele usa os repositórios apt
já configurados, sem PPAs ou scripts externos.

## 1. Autorizar SSH

No master, use uma chave existente ou crie uma exclusiva se esse arquivo não existir:

    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_sucacenter
    ssh-copy-id -i ~/.ssh/id_ed25519_sucacenter.pub cluster@192.168.1.103

Configure IdentityFile ~/.ssh/id_ed25519_sucacenter no bloco do host em
~/.ssh/config ou carregue a chave com ssh-add. Confirme o fingerprint por canal
confiável na primeira conexão. Com passphrase, use ssh-agent.

    ssh -o BatchMode=yes cluster@192.168.1.103 hostname

O setup não substitui chaves nem aceita fingerprints automaticamente. SSH
precisa funcionar antes da distribuição do pacote. Senhas não são gravadas.

## 2. Configuração

    bash sucacenter.sh step workspace
    nano ~/cluster/nodes
    nano ~/cluster/config/settings.env

Um host por linha; : representa local e os workers usam usuario@IPv4.
MANAGER_IP, LOCAL_SLOTS e WORKER_SLOTS configuram IP e concorrência. Os exemplos
do laboratório são preservados no repositório; configs ativas não são versionadas.

## 3. Executar

    bash sucacenter.sh setup --grant-docker-access

Rode como a conta operacional. Pode pedir sudo localmente e via SSH. Se cluster
não tem essa autorização, repetir não concede privilégios. Um administrador
precisa preparar serviços e dependências.

Depois de preparar os arquivos com setup --no-install, o administrador executa
em cada máquina:

    sudo bash /home/cluster/cluster/scripts/cluster-docker install --user cluster --grant-docker-access

Para distcc no worker:

    sudo bash /home/cluster/cluster/app/steps/distcc-worker.sh 192.168.1.110 192.168.1.103 4

Os comandos apt da etapa 02-dependencies.sh também podem ser executados pela conta
administradora. Não é necessário conceder sudo irrestrito a cluster.
O grupo docker equivale a root; abra uma NOVA sessão SSH após ser adicionado.
Não use chmod 666 no socket Docker.

## Etapas

| Nome | Onde | Verificação |
|---|---|---|
| preflight | master e setup local no worker | Linux/Python/ferramentas |
| workspace | cada conta | dirs, cópia operacional e symlinks |
| dependencies | cada máquina | apt --no-remove, cluster-doctor |
| ssh | master | autenticação e pacote; roda setup --local nos workers |
| distcc | ambos | GCC compatível, daemon LAN, test distcc |
| docker | ambos | Engine/Compose e grupo opcional |
| swarm | master | init/join e Ready/Active |

Use bash sucacenter.sh step NOME. Falhas retornam erro e preservam logs.
--no-install prepara arquivos, mas pula dependências, daemon distcc e Swarm.

## Firewall

distcc: TCP 3632 master → worker. Swarm: 2377/TCP, 7946/TCP+UDP e 4789/UDP entre
os nós. UFW ativo recebe regras restritas aos peers; não é desabilitado.
Outros firewalls/regras precisam ser configurados por um administrador.
Não exponha essas portas na internet.

Testar aplicação: bash sucacenter.sh test swarm. Publica TCP 18080 e baixa uma
imagem BusyBox do Docker Hub; a etapa setup não publica aplicações.
