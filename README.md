# SucaCenter

Laboratório de desenvolvimento com computadores reaproveitados: GNU Parallel,
distcc + ccache, Docker Engine e Swarm. Instalador modular, comandos operacionais
e testes, agora com Slurm, NFS, Samba, Gitea, replicacao e Portainer. Versão 1.3.0.

Fonte oficial: [lucasmrthomaz/sucacenter](https://github.com/lucasmrthomaz/sucacenter).
Codigo, documentacao e downloads sao mantidos neste mesmo repositorio.

## Portainer no Swarm

No worker01, depois que o Swarm estiver operacional:

    bash sucacenter.sh portainer validate
    bash sucacenter.sh portainer setup
    bash sucacenter.sh portainer status

A interface fica em `https://192.168.1.110:9443`. O servidor roda no manager e
o Agent em todos os nos Linux. Essa etapa e opt-in e preserva os outros servicos.
Nao exponha a interface diretamente na internet; veja [Portainer](docs/portainer.md).
sao mantidos neste mesmo repositorio.

## Replica automatica do shared

Para manter uma copia local em cada worker, com historico de ate 30 dias,
preservando o Samba/NFS existente:

    bash sucacenter.sh replication validate
    bash sucacenter.sh replication setup
    bash sucacenter.sh replication status

Configure o storage primeiro. A copia inicial e assincrona; setup nao significa
que os dados ja foram todos copiados. Leia [replicacao e recuperacao](docs/replicacao.md).
Essa etapa e explicita e nao e acionada por setup ou services run existentes.

## Versao unificada

As duas tarefas foram integradas neste pacote. Para o cluster que ja tem
distcc, Docker e Swarm configurados, execute no worker01 como cluster:

    bash sucacenter.sh services validate
    bash sucacenter.sh services run

Requer Ansible e a colecao ansible.posix no worker01. Para instalar com uma
conta autorizada: `sudo apt-get install ansible`; como cluster:
`ansible-galaxy collection install ansible.posix`.
A conta cluster precisa de sudo autorizado nos dois nos para os playbooks.
`--ask-become-pass` pede a senha; nao concede permissoes ausentes.

Para uma instalacao base seguida dos servicos: `bash sucacenter.sh setup --services`.
Use `--grant-docker-access` adicionalmente apenas se desejar conceder esse grupo.
O setup sem --services continua com o comportamento anterior.
O comando services usa os arquivos deste pacote por padrao. Leia
[mesclagem e limites](docs/mesclagem.md) antes da execucao.

## Comece aqui

Leia [instalação](docs/instalacao.md) antes de usar em máquinas novas.
Requer Linux Mint/Ubuntu/Debian com systemd, Bash 4+, Python 3.9+, SSH e conta
operacional não-root. A instalação de serviços exige autorização administrativa.

    git clone https://github.com/lucasmrthomaz/sucacenter.git
    cd sucacenter
    bash sucacenter.sh setup --grant-docker-access

Também pode extrair o ZIP da release e executar
o mesmo comando, sem Git no cluster. Não execute o setup inteiro com sudo.
O grupo docker concede privilégios equivalentes a root.

Para preparar somente arquivos, sem configurar serviços:

    bash sucacenter.sh setup --no-install

Configuração: ~/cluster/config/settings.env e ~/cluster/nodes. Arquivos existentes
são preservados. Exemplos: manager 192.168.1.110; worker cluster@192.168.1.103.
Em outra rede, execute step workspace e edite esses arquivos antes do setup.

## Operação

    bash sucacenter.sh status
    bash sucacenter.sh doctor
    bash sucacenter.sh step distcc
    bash sucacenter.sh step docker --grant-docker-access
    bash sucacenter.sh step swarm
    bash sucacenter.sh test distcc
    bash sucacenter.sh test benchmark
    bash sucacenter.sh test swarm
    cluster-help

Etapas completas, falhas e etapas puladas ficam em ~/cluster/config/state.
Cada execução verifica/reexecuta as etapas; marcadores antigos não pulam checks.
Falhas interrompem o setup, preservam logs e retornam erro. Corrija e repita.

## ZIP e instalador único

    python3 tools/package.py

Gera dist/sucacenter-1.3.0.zip, dist/bootstrap-sucacenter.sh e SHA256SUMS.
O .sh contém o projeto compactado, verifica o payload e extrai uma cópia em
~/cluster/installations/, sem baixar código:

    bash bootstrap-sucacenter.sh setup --grant-docker-access

Pacotes apt e imagens Docker ainda precisam de internet. Não é uma imagem de
disco nem instalador offline de todas as dependências.

## Documentação

- [Instalação](docs/instalacao.md)
- [Arquitetura](docs/arquitetura.md)
- [Comandos](docs/comandos.md)
- [Problemas comuns](docs/problemas-comuns.md)
- [Backup e restauração](docs/backup-restauracao.md)
- [Portainer](docs/portainer.md)
- [Validação e histórico](docs/validacao.md)
- [Mudanças](CHANGELOG.md)

## Validação

    bash tests/unit.sh

Verifica sintaxe/regressões sem configurar hosts reais. Os testes distcc e swarm
são separados porque operam no laboratório. O teste Swarm publica uma aplicação
na porta 18080. Confira os comandos de remoção na saída antes de repetir.

Sem senhas, chaves privadas, tokens de Swarm ou dados do usuário no repositório.
Não há licença de redistribuição concedida por este repositório.
