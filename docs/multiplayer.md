<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Multiplayer, servidor dedicado e deploy

## Multiplayer local


Escolha de um a quatro jogadores no menu inicial. Depois, cada jogador escolhe teclado ou um gamepad conectado e pode remapear individualmente movimento, pulo, ataque, troca de arma e recarga. Cada jogador recebe uma camera e HUD proprios.

- Analogico esquerdo: movimentar no gamepad
- `A`: pular
- `B`: correr
- `X`: atacar
- `LB`: faca
- `RB`: pistola
- `Y`: recarregar

Os botoes acima sao apenas o perfil inicial do gamepad e podem ser alterados no menu.

Para testar quatro telas sem controles conectados:

```bash
godot --path . -- --local-players=4
```

Durante a partida, `Esc` abre um menu semitransparente. Partidas locais ficam
pausadas; partidas em servidor continuam acontecendo enquanto o menu esta
aberto. O menu permite continuar, voltar ao menu principal ou sair do jogo.

## Servidor dedicado


O servidor usa ENet na porta `27015/udp` e descoberta de salas na porta
`27016/udp`. O ping exibido no navegador e um ping nativo do ENet medido na
porta do jogo; a porta de descoberta serve somente para metadados da sala. O
servidor Docker inicia por padrao no modo Sobrevivencia, com ondas progressivas
e objetivo de limpar todos os zumbis. Para
iniciar diretamente com o Godot instalado:

```bash
godot --headless --path . -- --server --server-port=27015 --survival
```

O menu separa `Jogar local` de `Multiplayer`. O modo local permite de um a
quatro jogadores na mesma maquina. No multiplayer, cada cliente ocupa um slot;
o servidor mostra no maximo quatro jogadores, a missao ativa e o ping. Salas na
LAN aparecem automaticamente. Servidores fora da LAN podem ser adicionados por
IP e porta e ficam salvos em `user://settings.cfg` para a proxima execucao.

## Release na VPS


Depois que a release 0.1 for publicada no repositorio, a instalacao limpa na VPS
pode ser feita assim:

```bash
sudo mkdir -p /srv/box-godot
sudo chown "$USER:$USER" /srv/box-godot
git clone <URL-do-repositorio> /srv/box-godot
cd /srv/box-godot
sudo ufw allow 27015/udp
sudo ufw deny 27015/tcp
docker compose --profile survival up -d --build   # ou --profile tdm / classic
docker compose ps
docker compose logs -f survival
```

No firewall do provedor da VPS, libere `27015/udp` e mantenha `27015/tcp`
bloqueada. Cada modo tem a sua porta (27015 sobrevivencia, 27017 mata-mata,
27019 classico); se outra porta for necessaria, defina `SURVIVAL_PORT` /
`TDM_PORT` / `CLASSIC_PORT` no compose, no firewall e no comando dos clientes
com o mesmo valor. Ver [modos-e-containers.md](modos-e-containers.md).

O branch do MVP procedural deve ser criado somente apos a release 0.1 estar
testada e marcada. Ele sera separado para nao misturar a experimentacao de
blueprints de cidade com a base multiplayer estavel.
