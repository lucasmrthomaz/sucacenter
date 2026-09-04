# Portainer

O Portainer CE administra o Docker Swarm pela interface web. O servidor roda em
uma replica no manager e o Agent roda globalmente nos nos Linux. A instalacao e
explicita e nao faz parte de `setup` nem de `services run`.

    bash sucacenter.sh portainer validate
    bash sucacenter.sh portainer setup
    bash sucacenter.sh portainer status

Depois do setup, abra `https://192.168.1.110:9443`. O certificado inicial e
autoassinado, portanto o navegador exibira um aviso. Crie a conta administrativa
na primeira abertura; o projeto nao gera, armazena ou imprime essa senha.

Somente 9443 e publicada, em modo host, no manager. As portas 8000, 9000 e 9001
nao sao publicadas. Nao crie redirecionamento dessa porta no roteador: Portainer
tem controle equivalente a root sobre os hosts Docker. Para acesso fora de casa,
use uma VPN privada, como Tailscale, sem Funnel publico.

O volume `portainer_data` e local ao worker01. Reexecutar setup atualiza os
servicos e preserva o volume. Isso nao e alta disponibilidade: faca backup do
volume antes de manutencao ou migracao do manager. O canal de imagem `lts` segue
a versao LTS oficial; valide e execute setup conscientemente para atualizar.

Se o status falhar, confira `docker stack services portainer` e
`docker service ps portainer_portainer --no-trunc`. O Agent usa o socket Docker e
e altamente privilegiado; mantenha o cluster e a LAN sob seu controle.
