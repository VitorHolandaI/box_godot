# Box Godot

Jogo desenvolvido com Godot 4 no Linux.

## Desenvolvimento

Abra `project.godot` no editor do Godot para iniciar o projeto.

## Controles

- `WASD`: movimentar
- `Espaco`: pular
- `Shift`: correr
- `1`: equipar faca
- `2`: equipar pistola
- Clique esquerdo ou `F`: atacar
- `R`: recarregar a pistola

## Cidade

O mapa procedural usa a seed definida pelo servidor para manter ruas e lotes
iguais em todos os clientes. A grade inclui apartamentos, casas, lojas,
mercados e shoppings solidos, com cores e orientacoes variadas. O solo e terra
texturizada procedural
e os arredores tem cara de apocalipse: uma muralha danificada cerca a area
jogavel, e um anel de ruinas, entulho e arvores secas separa a cidade da
floresta externa.

A floresta mistura arvores largas, pinheiros e arvores secas com arbustos,
rochas e tufos de grama. A opcao de qualidade grafica regula a densidade: 30
arvores por lado no baixo, 60 no medio e 100 no alto.

Zumbis surgem em interiores explicitamente marcados de predios modulares ou
longe do jogador, entre as arvores da floresta. Eles nunca nascem diretamente
nas ruas, e replicas multiplayer aparecem de imediato na posicao autoritativa.
A muralha bloqueia os jogadores, mas os zumbis atravessam os vao quebrados. O
alvo global da partida e de 600 zumbis vivos: eles aparecem gradualmente e cada
morte libera uma vaga que tambem e reposta aos poucos, independentemente da
quantidade de jogadores. O HUD de cada jogador mostra a quantidade viva atual.

Bots sem municao se aproximam em diagonal sem correr, orbitam na distancia da
faca e recuam quando entram no alcance de ataque do zumbi.

Cada horda possui um unico lider persistente que processa visao, audicao,
olfato e direcao. Os demais zumbis funcionam como drones. Quando duas hordas se
encontram, um dos lideres anteriores e sorteado como o novo cerebro do grupo.

## Safehouse e Sistema de Vidas

- **3 Vidas por Jogador**: Cada participante inicia com 3 vidas (`MAX_LIVES = 3`). Ao sofrer dano fatal, perde 1 vida e renasce dentro da Safehouse com vida e estamina cheias. Ao perder todas as 3 vidas, o jogador e eliminado da partida e o HUD exibe `[ELIMINADO]`.
- **Safehouse Fortificada de 2 Andares**: Localizada no lote central da cidade, conta com 4 estacoes de leitos e respawn demarcadas com kits medicos, bancada de armamentos, caixas de suprimento militar e dois pickups funcionais de municao (no terreo e no andar superior).
- **Porta Automatica**: O portal frontal abre para jogadores e zumbis proximos e fecha depois que a passagem fica vazia.
- **Segundo Andar e Mirante**: Acesso por escadaria de madeira real com corrimao e rampa suave, sacada de franco-atirador com sacos de areia, janela tatica e holofote defensivo voltado para a rua exterior.

## Propagacao Sonora de Tiros e Ecolocalizacao

- **Atenuacao Sonora por Distancia**: Cada disparo de pistola gera um estampido que se propaga por um raio de ate 65 metros. A intensidade diminui conforme a distancia da fonte do tiro.
- **Trajetoria Fixa**: A bala preserva a direcao escolhida no instante do disparo e nao persegue alvos depois de sair da arma.
- **Ecolocalizacao e Investigacao Lenta**: Zumbis que nao estao engajados em combate direto captam o som, calculam a direcao da fonte sonora e se deslocam em marcha cadenciada e cautelosa (velocidade reduzida em ~40%) em direcao ao local de onde veio o tiro.
- Se avistarem um sobrevivente pelo caminho, transitam imediatamente para perseguição e investida direta.

Ao morrer, o zumbi usa ragdoll articulado. O pescoco possui limites de inclinacao
e torcao para impedir que a cabeca atravesse o torso.

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

## Builds Linux e Windows

Com os export templates do Godot 4.7.2 instalados, gere os dois clientes com:

```bash
bash scripts/build_exports.sh
```

Os executaveis autocontidos e o arquivo `SHA256SUMS` ficam em `dist/`:

- Linux x86_64: `dist/box-godot-linux.x86_64`
- Windows x86_64: `dist/box-godot-windows.exe`

## Servidor dedicado

O servidor usa ENet na porta `27015/udp` e descoberta de salas na porta
`27016/udp`. Ele executa a simulacao autoritativa sem um jogador local. Para
iniciar diretamente com o Godot instalado:

```bash
godot --headless --path . -- --server --server-port=27015
```

O menu separa `Jogar local` de `Multiplayer`. O modo local permite de um a
quatro jogadores na mesma maquina. No multiplayer, cada cliente ocupa um slot;
o servidor mostra no maximo quatro jogadores, a missao ativa e o ping. Salas na
LAN aparecem automaticamente. Servidores fora da LAN podem ser adicionados por
IP e porta e ficam salvos em `user://settings.cfg` para a proxima execucao.

## Cidade procedural experimental

A branch `feature/procedural-city-mvp` inclui o modo experimental. Para abrir
uma partida local usando blueprints procedurais, execute:

```bash
./dist/box-godot-linux.x86_64 -- --procedural-city --world-seed=18273
```

Inicie uma partida local no menu. A mesma seed reconstrui a mesma cidade; troque
`18273` por outra seed para obter outro parcelamento deterministico. Em rede, o
servidor envia o modo e a seed no handshake antes de carregar o mapa, portanto
o cliente nao precisa desses argumentos. O modo experimental nao altera a
release estavel ate ser promovido para `main`.

Para construir e iniciar o container isolado:

```bash
docker compose up --build -d
docker compose logs -f game-server
```

Na VPS, publique `27015/udp` e `27016/udp` no firewall do sistema e no firewall
do provedor para permitir jogo e status das salas. O container roda como usuario sem privilegios, com filesystem somente
leitura, sem capabilities Linux e com limites de CPU, memoria e processos.

Exemplo para uma VPS com UFW:

```bash
sudo ufw allow 27015/udp
sudo ufw allow 27016/udp
sudo ufw status
```

Abra tambem `27015/udp` no security group ou firewall do provedor. Nao abra a
porta TCP: o transporte do jogo e UDP. Para usar outra porta alta, defina o
mesmo valor ao subir o container e ao iniciar clientes por linha de comando:

```bash
GAME_SERVER_PORT=32000 docker compose up --build -d
./box-godot-linux.x86_64 -- --server-port=32000
```

Ao usar uma porta customizada, publique tambem a porta seguinte para descoberta
(`GAME_SERVER_DISCOVERY_PORT=32001` no exemplo acima).

O menu usa `27015` por padrao. Em cada computador, escolha `Multiplayer`,
selecione a sala online e entre com um jogador. Este prototipo ainda nao
autentica jogadores; para um teste privado, prefira limitar as regras UDP aos
IPs publicos dos computadores autorizados.

Para copiar apenas os arquivos de implantacao para a VPS:

```bash
rsync -av --exclude .git --exclude .godot --exclude .ai-memory.toml . usuario@vps:/srv/box-godot/
```

Depois, na VPS:

```bash
cd /srv/box-godot
docker compose up --build -d
```

Para testar a cidade procedural experimental na VPS, use a branch
`feature/procedural-city-mvp` no servidor e no cliente:

```bash
git fetch origin
git switch feature/procedural-city-mvp
git pull --ff-only
docker compose up --build -d
```

O compose inicia a cidade procedural por padrao e cria uma seed a partir do ID
do container. Para forcar uma seed especifica, defina
`GAME_SERVER_WORLD_SEED=18273`. O cliente deve ser aberto normalmente: escolha
`Conectar ao servidor` e informe somente o IP ou dominio e a porta. O servidor
envia a seed e o modo procedural durante a conexao.

Para iniciar o modo sobrevivencia no servidor dedicado, use:

```bash
GAME_SERVER_GAME_MODE=--survival docker compose up --build -d
```

O modo possui ondas de 10, 20, 30, 40, 60, 80, 120, 140, 160 e depois
incrementos de 20 ate a onda final de 600 zumbis. O cliente continua usando
somente o IP e a porta; a configuracao e enviada pelo servidor.

## Release 0.1 na VPS

Depois que a release 0.1 for publicada no repositorio, a instalacao limpa na VPS
pode ser feita assim:

```bash
sudo mkdir -p /srv/box-godot
sudo chown "$USER:$USER" /srv/box-godot
git clone git@git-interno:vitor/box_godot.git /srv/box-godot
cd /srv/box-godot
sudo ufw allow 27015/udp
sudo ufw deny 27015/tcp
docker compose up --build -d
docker compose ps
docker compose logs -f game-server
```

No firewall do provedor da VPS, libere `27015/udp` e mantenha `27015/tcp`
bloqueada. Se outra porta for necessaria, defina `GAME_SERVER_PORT` no compose,
no firewall e no comando dos clientes com o mesmo valor.

O branch do MVP procedural deve ser criado somente apos a release 0.1 estar
testada e marcada. Ele sera separado para nao misturar a experimentacao de
blueprints de cidade com a base multiplayer estavel.

## Testes automatizados

Teste nativo de servidor dedicado:

```bash
bash scripts/test_dedicated.sh
```

Teste completo do container:

```bash
bash scripts/test_container.sh
```

O cliente-bot conecta com um slot, move o personagem, equipa a pistola e atira.
O teste so passa depois que o cliente observa movimento, consumo de stamina,
projetil visual e a morte de um zumbi.
Entrada nao predeterminada e erros de script embarcam nesses smoke tests.
