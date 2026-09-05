# Monitoramento OnePage

Execute no master, como a conta que já acessa os workers por SSH:

```bash
bash bootstrap-monitoring.sh
```

Informe os IPs ou nomes DNS separados por espaços, com `usuario@host` quando
necessário. O master é incluído automaticamente. Por exemplo:

```bash
HOSTS="cluster@192.168.1.103" bash bootstrap-monitoring.sh
```

O arquivo é autônomo: também pode ser baixado sozinho da raiz deste repositório.
Não é executado implicitamente por `sucacenter.sh setup` ou `services run`.

## Instalação e acesso

Requer Debian, Ubuntu ou MX Linux, arquitetura x86_64/arm64, internet para APT e
imagens Docker, SSH nos remotos e sudo autorizado (ou conexão root).
Usa systemd ou os scripts SysVinit dos pacotes da distribuição. A compatibilidade
depende de os repositórios fornecerem Docker e Node Exporter para esse sistema.

O instalador configura Node Exporter em todos os nós, Docker/Compose no master
quando ausentes, Prometheus, datasource e dashboard do Grafana. Pode solicitar
senhas SSH/sudo; usa as chaves e o agente SSH da conta que o executa. Chaves de
hosts novos são registradas; alterações de chaves existentes são recusadas.

Ao terminar, mostra o endereço do dashboard, usuário `admin` e a senha inicial
gerada. A senha não está no código nem no Compose. Ela fica em
`/opt/sucacenter/monitoring/secrets/grafana_admin_password`, dentro de um diretório
acessível somente por root. Se alterá-la na interface, use a senha nova: reexecutar
o script não redefine a senha de um banco Grafana existente.

| Serviço | Endereço/porta |
| --- | --- |
| Node Exporter | 9100 em cada nó, sem autenticação |
| Prometheus | `127.0.0.1:9090` no master |
| Grafana | 3000 ou, se ocupada, 3001 no master |

**O Gitea do SucaCenter já usa 3000.** Nesse caso, o instalador seleciona 3001 e
salva a escolha. Se as duas estiverem ocupadas, defina `GRAFANA_PORT=3002`, por
exemplo. `GRAFANA_BIND` permite limitar o endereço IPv4 de escuta. A porta escolhida
também é usada na validação e no link final.

Use rede local/VPN e restrinja 9100 ao master. Restrinja a porta do Grafana aos
operadores. O script não muda o firewall e não configura TLS. Os containers usam
a rede do host Linux; o Prometheus consulta os nós a partir da rede do master.

## Dashboard

Uma linha por nó mostra UP/DOWN, CPU, RAM, filesystem mais cheio, RX e TX.
CPU e rede precisam de pelo menos duas coletas (aproximadamente 30 segundos).
DOWN significa falha de coleta; pode ser máquina desligada, serviço parado,
firewall ou problema de rede. Métricas de nós DOWN ficam sem dados.
RX/TX soma interfaces, excluindo loopback e interfaces Docker comuns; bonds e
interfaces virtuais adicionais podem resultar em contagem duplicada.

## Reexecução e manutenção

A lista de hosts, porta, senha inicial, imagens fixadas por digest e volumes de
dados são preservados. Para alterar os alvos:

```bash
HOSTS="cluster@192.168.1.103 cluster@worker02" bash bootstrap-monitoring.sh
```

Use `HOSTS="-"` para somente o master. Retirar um alvo da lista não desinstala o
exporter remoto. Literais IPv6 não são aceitos na lista; use DNS. A porta SSH pode
ser definida com `SSH_PORT=2222` para todas as conexões.

Configurações ficam em `/opt/sucacenter/monitoring`; versões anteriores em
`backups/`. Alterações anteriores do arquivo de configuração do exporter ficam
em `/var/backups/sucacenter-node-exporter.*` em cada nó. Esses backups não incluem
os bancos/volumes de dados e não substituem um backup operacional.

Reexecutar recria os dois containers, com breve interrupção, preservando os
volumes. O dashboard provisionado é gerenciado pelo script; duplique-o no Grafana
se quiser uma cópia editável. Prometheus retém 15 dias por padrão.

Para atualizar as imagens, remova explicitamente `images.json` no diretório de
instalação e reexecute; isso selecionará as imagens configuradas no topo do
arquivo. O plugin Compose instalado manualmente não se atualiza sozinho.

```bash
sudo docker compose -p sucacenter-monitoring \
  -f /opt/sucacenter/monitoring/docker-compose.yml logs --tail=100
```

O instalador valida a configuração com promtool antes de substituir arquivos,
verifica todos os endpoints, todos os alvos UP no Prometheus e as consultas do
dashboard. Falhas retornam código diferente de zero. Corrija a causa e reexecute;
não há rollback automático de pacotes ou serviços.

Os testes do repositório verificam sintaxe e geração sem alterar máquinas reais.
A instalação completa deve ser validada no laboratório.
