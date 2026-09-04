# SucaCenter bootstrap

Extraia o ZIP numa maquina Linux com Bash 4+ e Python 3. Os cinco playbooks
e o inventory fornecidos estao incluidos. Nenhum arquivo falta.
Na versao integrada, gitea.yml reutiliza Docker e Compose da etapa docker;
o original foi preservado em originals/gitea.yml. Veja ../docs/mesclagem.md.
O healthcheck executa por ultimo e mostra hostname, CPU e RAM dos workers;
ele nao verifica a saude de Slurm, NFS, Samba ou Gitea.

Uso (na pasta extraida):

    bash bootstrap-sucacenter.sh --prepare
    bash bootstrap-sucacenter.sh --validate
    bash bootstrap-sucacenter.sh --run

Sem argumento, executa --run. --prepare apenas coleta arquivos locais;
--validate inclui acesso aos nos por Ansible ping, mas nao provisiona servicos.
O destino e ~/sucacenter-bootstrap. O script e copiado para esse destino
e pode ser reexecutado a partir dele. Cada coleta preserva o destino anterior
em sucacenter-bootstrap.backup-*/previous-directory ao lado dele.
As fontes nao sao alteradas. Execute apenas uma instancia de cada vez.

Fontes: ~/sucacenter-user primeiro, depois playbooks/ do pacote por arquivo.
Inventory: ~/inventory.ini, depois inventory.ini na fonte e no pacote.
SUCACENTER_SOURCE_DIR e SUCACENTER_INVENTORY selecionam fontes explicitas,
sem fallback para os respectivos arquivos. SUCACENTER_BOOTSTRAP_DIR permite
outro caminho, mas o nome final deve ser sucacenter-bootstrap.
Arquivos auxiliares de futuros playbooks (roles, templates, vars) precisam
ser incorporados separadamente; os cinco arquivos atuais sao autocontidos.

Checkpoints:

1. Confira missing-playbooks.txt e os arquivos coletados.
2. Instale Ansible no controlador de execucao e a colecao usada pelo NFS:
   `ansible-galaxy collection install ansible.posix`. SSH e Python 3 sao exigidos.
3. O inventory incluido define workers=worker01,worker02 e controller=worker01,
   com worker01=192.168.1.110 e worker02=192.168.1.103, usuario SSH cluster
   e Python remoto /usr/bin/python3. O script verifica os IPs e grupos sem
   reescrever o inventory. Configure a chave SSH e acesso sudo do usuario.
   Se houver inventory em ~/inventory.ini, ele tem prioridade; para usar
   explicitamente o incluido, prefixe o comando com
   `SUCACENTER_INVENTORY="$PWD/inventory.ini"` na pasta extraida.
4. --validate verifica inventory, syntax-check individual e site.yml, e ping
   Ansible (SSH + Python remoto). Nenhum provisionamento acontece se falhar.
5. --run pede a senha sudo com --ask-become-pass e executa Slurm, NFS,
   Samba, Gitea e, se encontrado, healthcheck. A primeira falha interrompe o fluxo.

Pre-requisitos dos playbooks recebidos: Debian/Ubuntu com APT e systemd;
usuario e grupo cluster ja existentes; acesso de escrita de cluster ao NFS;
Docker e Compose ja instalados pela etapa docker. Samba nao cadastra senha automaticamente:
configure a conta com `sudo smbpasswd -a cluster` no worker01 para acesso SMB.
Slurm usa CPU/memoria fixas do arquivo original; confira contra o hardware.

A coleta pode ser repetida, mas os playbooks originais nao garantem uma
execucao sem mudancas: Slurm reinicia slurmctld, NFS regrava testes com data,
e Gitea usa a imagem latest e faz pull. Backups sao do pacote local, nao dos
dados dos servicos. As falhas remotas nao desfazem tarefas ja aplicadas.
