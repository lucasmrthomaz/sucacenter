# Mesclagem das duas tarefas

Base: tarefa "Criar bootstrap do cluster", projeto sucacenter 1.0.0,
commit local 39ef414d67aaa82de37715567035d670f2e3b2f9.
Adicao: pacote Ansible desta tarefa, com os cinco playbooks e inventory
fornecidos pelo usuario. Resultado: versao unificada 1.1.0 no repositorio
https://github.com/lucasmrthomaz/sucacenter.

## Ordem e responsabilidades

1. Setup base: workspace, dependencias, SSH, distcc, Docker e Swarm.
2. Services: coleta com backup, inventory, syntax-check, conectividade Ansible.
3. Provisionamento: Slurm, NFS, Samba, Gitea, healthcheck de hardware.

Em um cluster ja configurado, use services validate e services run. Nao e
necessario repetir o setup base. A opcao setup --services combina as etapas;
o setup remoto nao recebe --services, evitando executar o Ansible nos workers.
O modo prepare nao configura servicos. O modo validate usa SSH, mas nao aplica
os playbooks. Services run usa --ask-become-pass e para na primeira falha.

## Conflitos resolvidos

- Um unico ponto de entrada: sucacenter.sh. O instalador autocontido extrai
  este mesmo projeto. O coletor Ansible fica em ansible/bootstrap-sucacenter.sh.
- Gitea nao instala mais docker.io ou plugin Compose: verifica o motor/plugin
  ja configurados pela etapa docker. Isso evita misturar pacotes do sistema e
  Docker CE. O restante do playbook foi preservado, assim como o original em
  ansible/originals/gitea.yml. A execucao nao migra Gitea para Swarm; segue Compose.
- O comando services prioriza o pacote revisado. Fontes alternativas exigem
  SUCACENTER_SOURCE_DIR e/ou SUCACENTER_INVENTORY explicitos. O coletor standalone
  ainda possui a busca em ~/sucacenter-user e ~/inventory.ini.
- ~/cluster/nodes e settings.env continuam preservados. O inventory Ansible
  inclui os mesmos dois IPs. Se ampliar os nos, revise ambos os inventarios.
- ~/cluster/shared-files e uma copia local por maquina usada por rsync;
  /mnt/shared e NFS servido por worker01 em /srv/sucacenter/shared e exposto
  por Samba. Nao foram unidos por symlink: isso sincronizaria o NFS consigo mesmo
  e deixaria de oferecer copias em discos distintos.

## Limites conhecidos antes da execucao

A conta cluster e o grupo cluster precisam existir. O historico da outra tarefa
mostrou restricoes de sudo para cluster: senha sudo so funciona com autorizacao
administrativa existente. A configuracao de senha SMB e separada (smbpasswd).
Slurm muda os hostnames para worker01/worker02 e usa CPU/RAM fixas. Verifique o
estado do Swarm depois dessa mudanca; nao ha execucao real desta integracao.
Slurm, distcc e Swarm compartilham CPU/RAM, mas nao coordenam recursos entre si.
O healthcheck final apenas mostra hardware, nao comprova a saude dos servicos.
Slurm reinicia o controller, NFS atualiza arquivos de teste e Gitea faz pull de
latest em cada execucao; a idempotencia integral dos playbooks nao e garantida.
Backups automaticos protegem o pacote, nao dados ativos ou volumes dos servicos.

## Entrega e publicacao

O ZIP e o instalador unico sao gerados por tools/package.py a partir deste
diretorio e distribuidos na release v1.1.0 do mesmo repositorio da base.
A release v1.0.0 permanece disponivel como historico. Os arquivos incluem
IPs privados do laboratorio, mas nao senhas. Mudancas futuras devem ser
feitas neste projeto e empacotadas por tools/package.py.
