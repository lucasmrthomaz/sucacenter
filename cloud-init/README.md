# Bootstrap dos workers com cloud-init

Antes do Ansible, o primeiro boot cria `cluster` (grupo primario `cluster`),
autoriza a chave publica do master, libera sudo NOPASSWD, instala Python 3,
sudo e OpenSSH e configura hostname/rede. NOPASSWD concede administracao completa.
A chave privada fica somente no master; cada VM gera suas proprias chaves de host.

Use uma **cloud image Ubuntu Server 24.04 com cloud-init, Netplan e systemd**,
com acesso aos repositorios APT. Uma ISO de instalacao comum nao consome este
seed automaticamente. Debian exige conferir o suporte da imagem ao formato de
rede v2; estes exemplos usam Netplan. Nao aplique sobre workers ja configurados.

## Arquivos

- `common/user-data.yaml`: template unico de usuario, SSH, sudo e pacotes.
- `nodes/<worker>/meta-data.yaml`: hostname e identidade unica da instancia.
- `nodes/<worker>/network-config.yaml`: interface, IP, rota e DNS de cada VM.
- `render.py`: insere uma chave publica validada e produz os tres arquivos NoCloud.

Os IPs **de exemplo** sao worker03=`192.168.1.113`, worker04=`192.168.1.114`
e worker05=`192.168.1.115`, todos `/24`, interface `ens18`, gateway/DNS
`192.168.1.1`. Confira IPs livres fora do pool DHCP (ou reservados) e o nome
real da interface pelo console (`ip -br link`). Edite cada network-config
antes de gerar. Para reserva DHCP, use `dhcp4: true` e remova `addresses`,
`routes` e `nameservers`; reserve o IP pelo MAC no servidor DHCP.

## Gerar e iniciar

No controlador, com Python 3.9+ e `ssh-keygen` (pacote `openssh-client`),
execute na raiz do clone do repositorio:

```bash
for node in worker03 worker04 worker05; do
  python3 cloud-init/render.py "$node" \
    --public-key "$HOME/.ssh/id_ed25519.pub" \
    --output "cloud-init/generated/$node"
done
```

O gerador recusa chaves privadas, chaves publicas invalidas e destinos existentes.
Aceita Ed25519, RSA e ECDSA OpenSSH. Nao envie o template com placeholder a VM.
Para regenerar, escolha outra pasta de saida. `generated/` fica fora do Git;
guarde arquivos personalizados e seeds fora de commits. Esta pasta esta disponivel
no clone Git; o empacotador de releases existente nao a inclui.

Em um host Linux com cloud-init e `cloud-image-utils`, valide e crie o disco seed:

```bash
for node in worker03 worker04 worker05; do
  seed="cloud-init/generated/$node"
  cloud-init schema --config-file "$seed/user-data"
  cloud-localds --network-config="$seed/network-config" \
    "$seed/seed.img" "$seed/user-data" "$seed/meta-data"
done
```

Anexe `seed.img` da respectiva VM como disco adicional no hypervisor **antes do
primeiro boot**, junto a um disco de sistema novo baseado na cloud image. Use o
disco de sistema como dispositivo de boot. O seed e NoCloud, nao um instalador.
NoCloud exige nomes `user-data`, `meta-data` e `network-config`, sem extensao,
na midia; o gerador e cloud-localds cuidam disso.

Para adicionar outro worker, copie uma pasta em `nodes/`, altere `local-hostname`,
`instance-id` e a rede. Mantenha o instance-id entre reinicios da mesma VM; use
um novo para uma nova instancia e um disco de imagem limpo. Apenas trocar o
seed depois do primeiro boot nao garante que cloud-init execute novamente.

## Verificar e entregar ao Ansible

No console de cada VM, aguarde `sudo cloud-init status --wait` terminar sem erros.
Se falhar, consulte `/var/log/cloud-init.log` e `/var/log/cloud-init-output.log`.
No master (ajuste o IP), valide SSH, Python e sudo:

```bash
ssh -i "$HOME/.ssh/id_ed25519" cluster@192.168.1.113 \
  'hostname; python3 --version; sudo -n id; systemctl is-active ssh'
```

Confira a impressao digital SSH pelo console no primeiro acesso. O inventario
existente fica preservado. Para testar apenas as VMs novas, crie um inventario
local `cloud-init/generated/inventory.ini`, ajustando os IPs:

```ini
[workers]
worker03 ansible_host=192.168.1.113
worker04 ansible_host=192.168.1.114
worker05 ansible_host=192.168.1.115

[workers:vars]
ansible_user=cluster
ansible_python_interpreter=/usr/bin/python3
```

```bash
ansible -i cloud-init/generated/inventory.ini workers -m ping
ansible -i cloud-init/generated/inventory.ini workers -b -m command -a 'id -u'
```

Depois adicione os nos ao inventario operacional e execute o playbook desejado.
Cloud-init nao instala servicos do cluster nem dispara Ansible. O wrapper atual
`ansible/bootstrap-sucacenter.sh` ainda pede senha com `--ask-become-pass`;
NOPASSWD permite usar Ansible diretamente sem esse argumento.

Referencias: [NoCloud](https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html)
e [rede v2](https://docs.cloud-init.io/en/latest/reference/network-config-format-v2.html).
