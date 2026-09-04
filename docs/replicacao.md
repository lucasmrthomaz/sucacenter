# Replica automatica do shared com historico

O worker01 continua atendendo Samba/NFS em /srv/sucacenter/shared.
Syncthing envia as mudancas para /srv/sucacenter/replica-shared no disco
local do worker02. Outros hosts adicionados a workers tambem recebem uma
replica local. Nao sao usados /mnt/shared, volumes Docker ou dados do Gitea.
O nome da pasta pode ser igual nas replicas, mas o disco e de cada maquina.

## Ativar no cluster existente

No worker01, como cluster, a partir do repositorio atualizado:

    git pull --ff-only
    bash sucacenter.sh replication validate
    bash sucacenter.sh replication setup
    bash sucacenter.sh replication status

Ou use o instalador unico da release com os mesmos argumentos:

    bash bootstrap-sucacenter.sh replication setup
    bash bootstrap-sucacenter.sh replication status

Requer Ansible no host de execucao, SSH e sudo autorizado nos dois nos.
Setup pede a senha de become, instala o pacote syncthing da distribuicao,
troca os IDs automaticamente e habilita sucacenter-syncthing.service no boot.
Nao precisa fazer login, deixar terminal aberto nem agendar comandos.
O pacote deve oferecer Syncthing com REST config (1.12 ou mais recente);
testado com 1.29.5. Nenhum repositorio APT externo e adicionado.

O comando validate so confere inventory e sintaxe, sem acesso remoto.
Setup faz os checks reais de disco, conta, pasta e conectividade da API.
Configure storage primeiro: a origem precisa existir, nunca e criada vazia
por esta etapa. Setup nao reexecuta Slurm, Docker, Swarm, Samba ou Gitea.

## Comportamento

- Origem sendonly; replicas receiveonly. Continue editando pela pasta original
  ou pelos compartilhamentos existentes. Edicoes diretas na replica nao voltam
  para a origem e sao reportadas como divergencia.
- Historico simple com ate 20 versoes por arquivo e limpeza apos 30 dias em
  .stversions de cada replica. Ele guarda versoes substituidas/excluidas por
  mudancas recebidas. Versoes alem do limite de 20 podem sair antes dos 30 dias.
  Nao guarda edicoes que ocorreram entre sincronizacoes nem mudancas locais.
- Exclusoes tambem se propagam; o historico permite recuperar as versoes
  arquivadas durante a janela de retencao. Isto nao substitui backup externo.
- Sincronizacao via observacao de arquivos mais varredura a cada 10 minutos.
  Eventos de arquivos podem levar segundos; a copia inicial pode levar horas.
  A transferencia e limitada a cerca de 10 MiB/s por instancia, com prioridade
  baixa e CPUQuota=50% (metade de um core) para poupar as maquinas antigas.
- Deixa de gravar quando o limite de 5% de disco livre e atingido. Dimensione
  cada replica para o total do shared mais o historico; nao ha quota por pasta.

Setup concluido significa configurado, nao necessariamente copia concluida.
Status so passa quando os peers estao conectados, sincronizados e sem erros
ou alteracoes locais na replica. Offline, copia em andamento e divergencias
retornam erro/pending com detalhes. Dados ainda em transito podem ser perdidos
se a origem falhar antes de sincronizar.

## Rede e isolamento

Dados: TCP 22001, ligado apenas ao IP LAN de cada no; dispositivos pareados
por ID. Sem descoberta publica, relays, UPnP ou abertura da GUI na rede.
Com UFW ativo, setup libera apenas os IPs dos peers nessa porta; nao habilita
UFW. Se houver outro firewall, permita TCP 22001 entre os nos.
GUI/API: 127.0.0.1:8385. Chaves sao geradas em cada no e ficam em
/var/lib/sucacenter-syncthing (0700). Nao copie esse estado de um no para outro:
isso duplicaria a identidade. Uma instancia pessoal de Syncthing nao e alterada.
As configuracoes anteriores sao preservadas ali com permissao privada.

Para ver a GUI do worker02 a partir do seu computador:

    ssh -N -L 8385:127.0.0.1:8385 cluster@192.168.1.103

Abra http://127.0.0.1:8385 no navegador desse computador. O tunel precisa ficar
aberto. Nao exponha 8385 no roteador. Administradores locais tem acesso a GUI.

## Protecoes de disco

Recusa NFS/CIFS e outros filesystems nao locais, links nos caminhos principais,
submontagens dentro da pasta e destino preexistente com dados nao gerenciados.
Nao formata discos nem migra pastas. Filesystems aceitos: ext2/3/4, XFS,
Btrfs, ZFS e F2FS. A identidade da montagem e registrada e conferida ao iniciar.
Se um disco desaparecer, mudar de identidade ou perder .stfolder, a instancia
para em vez de criar uma nova origem vazia. Corrija/restaure a montagem; nao
apague marcadores para forcar a sincronizacao.

Nao execute outra instancia Syncthing sobre essas mesmas pastas. Bancos ativos
e conjuntos de arquivos que exigem consistencia transacional precisam de
backups proprios; a sincronizacao e por arquivo.

## Recuperacao de um arquivo

No worker02, pare temporariamente somente a replica:

    sudo systemctl stop sucacenter-syncthing

Pela conta cluster, inspecione /srv/sucacenter/replica-shared/.stversions e
copie a versao desejada para uma pasta de recuperacao fora da replica. Apos
conferir, coloque o arquivo restaurado na origem /srv/sucacenter/shared do
worker01. Entao retome:

    sudo systemctl start sucacenter-syncthing

Nao use Revert Local Changes ou Override Changes para restaurar historico.
Se o worker01 morreu, primeiro preserve a replica e .stversions em outra copia.
Ela permanece acessivel localmente, mas NFS/Samba nao mudam automaticamente
para worker02. Promover outra origem e um procedimento separado, manual.

Logs: `journalctl -u sucacenter-syncthing -n 100 --no-pager` em cada no.
Para pausar indefinidamente: `sudo systemctl disable --now sucacenter-syncthing`.
Isso preserva os arquivos e o historico; nao desinstala Syncthing.

## Referencias e testes

- https://docs.syncthing.net/users/foldertypes.html
- https://docs.syncthing.net/users/versioning.html
- https://docs.syncthing.net/rest/config.html
- https://docs.syncthing.net/rest/db-completion-get.html

Testes unitarios: `bash tests/unit.sh`.
Teste opcional com dois processos Syncthing reais em pastas temporarias Linux:
`python3 tests/replication-live.py /caminho/para/syncthing`.
Esse teste usa somente loopback, nao instala servicos nem acessa o cluster.
