# Compilação distribuída Rust

Playbook independente: `ansible/sccache.yml`. Mantém o inventory existente e
reutiliza `workers`, `controller`, APT, systemd e o usuário `cluster`.
`worker01` é scheduler e cliente; todos os demais membros de `workers` são
build servers. Não importa `site.yml` e não reconfigura Slurm, Docker ou NFS.
Os defaults estão em `ansible/roles/sccache/defaults/main.yml`; podem ser
sobrescritos em inventory, `group_vars/workers.yml`, `host_vars` ou com `-e`.

## Executar

Na raiz do repositório, em um controlador Ansible Linux com SSH e sudo nos nós:

```bash
ansible-playbook -i ansible/inventory.ini ansible/sccache.yml --syntax-check
ansible-playbook -i ansible/inventory.ini ansible/sccache.yml -K
# Provisiona/verifica e exige também uma compilação Rust remota bem-sucedida:
ansible-playbook -i ansible/inventory.ini ansible/sccache.yml -K -e sccache_smoke_test=true
```

Use o inventory completo, sem `--limit` ou `--check`. A criação e distribuição
de identidades exige execução real; `--check` é recusado antes das alterações.
Ansible-core 2.16+; apenas módulos builtin, sem collections adicionais.
Os nós precisam de Debian/Ubuntu com systemd, Python 3, sudo, arquitetura
64 bits x86_64 ou aarch64, acesso HTTPS aos mirrors APT, static.rust-lang.org e
crates.io, disco local e suporte a overlayfs/bubblewrap. Use a mesma arquitetura
e versão da distribuição nos nós: os workers executam o toolchain do cliente.
O usuário `cluster` já deve existir no worker01, como no bootstrap atual.

Rust 1.98.1 é instalado em `/opt/sucacenter/rust-1.98.1` a partir do arquivo
oficial com SHA256 verificado. sccache 0.17.0 é compilado em cada nó, sem root,
com `--locked --no-default-features --features dist-client,dist-server`.
Os executáveis finais pertencem a root. A primeira instalação pode demorar
e consumir vários GB; o padrão usa um job de compilação por nó. Reexecuções
preservam toolchain, binários, chaves e certificados válidos.

No worker01, como `cluster`:

```bash
. /etc/profile.d/sucacenter-sccache.sh
cargo build --release
sccache --dist-status
sccache --show-stats
```

O perfil configura `RUSTC_WRAPPER`, `CARGO_INCREMENTAL=0`, o PATH do Rust
fixado e a porta local 4227. Faça login novamente ou carregue o perfil acima.
Scripts não interativos/CI devem carregar esse mesmo arquivo. Configurações
Cargo existentes não são sobrescritas. O sccache inicia seu daemon local sob
demanda para o usuário `cluster`. Projetos que exigem outro
Rust podem ajustar o PATH/RUSTC; o toolchain realmente usado é empacotado
pelo sccache. Nem toda etapa é distribuível: linking e outras etapas podem
continuar locais; cache hits também não geram trabalho remoto.

## Rede e identidade

| Destino | Porta TCP | Origem permitida |
| --- | --- | --- |
| worker01, nginx TLS dedicado | 10601 | IPs de `workers` |
| worker01, scheduler HTTP | 10600 | loopback apenas |
| Cada build server | 10501 | worker01 (scheduler e cliente) |
| worker01, daemon cliente | 4227 | loopback apenas |

Nginx roda como instância separada com configuração em `/etc/sccache/nginx.conf`;
não altera sites nem o serviço nginx já existente. Sobrescreve `X-Real-IP`
com o endereço real e aplica allowlist do inventory. Builders usam o TLS
nativo do sccache, com certificados comunicados pelo scheduler autenticado.
Se UFW estiver ativo, adiciona regras limitadas aos peers, seguindo o padrão
de `replication.yml`; não habilita UFW nem remove regras existentes. Para
nftables, firewalld ou firewall externo, aplique a matriz acima manualmente.
`sccache_manage_ufw=false` desativa a gestão. Regras antigas após mudar IP/porta
devem ser removidas pelo administrador; regras amplas preexistentes permanecem.

As credenciais são geradas no worker01 usando o gerador criptográfico do SO,
persistidas em `/etc/sccache/private` (0700) e nunca gravadas no repositório.
O cliente recebe token próprio; cada builder recebe JWT limitado ao seu IP e
porta. A chave mestra JWT e a chave da CA permanecem no scheduler. As tasks
com segredos usam `no_log`; configurações privadas têm modo 0600/0640.
Não configure cache de facts persistente nem callbacks que capturem variáveis
privadas. O backend overlay requer root nos builders para os namespaces/mounts;
o scheduler e o cliente usam contas sem root.

Uma CA privada assina o certificado do scheduler e somente seu certificado
público é instalado no trust store dos nós. TLS é validado, sem `-k`.
O certificado do scheduler dura um ano e é renovado nas reexecuções quando
faltam menos de 30 dias ou o IP muda. Reexecute pelo menos mensalmente.
A CA dura dez anos; a proximidade do vencimento provoca erro para permitir
rotação coordenada. Guarde backup protegido de `/etc/sccache/private`.
Para rotação de tokens, substitua apenas os campos em `secrets.json` por novos
valores criptográficos (chave JWT: base64url de 32 bytes) e reexecute em todos
os nós; mudanças reiniciam os serviços afetados. Não remova a CA para rotacionar
somente tokens. Agende alterações fora de builds ativos, pois podem interrompê-los.

## Verificação e diagnóstico

O teste final verifica HTTPS de cada nó, quantidade esperada de servidores
registrados, conexão do worker01 às portas dos builders e `--dist-status`
através do daemon real. Isso comprova conectividade/registro, não compilação.
O teste opcional cria uma biblioteca Rust única e sem dependências externas,
executa Cargo e exige aumento no contador de compilações distribuídas; um
fallback exclusivamente local falha. Rode sem outras compilações concorrentes
para atribuir o incremento ao teste. O diretório temporário é removido.

```bash
sudo journalctl -u sccache-scheduler -u sccache-tls -n 100
# Nos demais workers:
sudo journalctl -u sccache-builder -n 100
```

Se há registro mas o teste remoto falha, examine overlayfs/bubblewrap,
restrições de namespaces/AppArmor, arquitetura e bibliotecas do toolchain.
O playbook não desabilita políticas de segurança do sistema globalmente.

Referências: [distribuição e autenticação sccache 0.17.0](https://github.com/mozilla/sccache/blob/v0.17.0/docs/Distributed.md),
[quickstart oficial](https://github.com/mozilla/sccache/blob/v0.17.0/docs/DistributedQuickstart.md),
[versões oficiais Rust](https://blog.rust-lang.org/releases/).
