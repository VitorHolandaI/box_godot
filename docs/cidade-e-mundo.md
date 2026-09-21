<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Cidade e mundo procedural

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
docker compose --profile survival up -d --build
docker compose logs -f survival
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
SURVIVAL_PORT=32000 docker compose --profile survival up -d --build
./box-godot-linux.x86_64 -- --server-port=32000
```

Ao usar uma porta customizada, publique tambem a porta seguinte para descoberta
(`SURVIVAL_DISCOVERY_PORT=32001` no exemplo acima).

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
docker compose --profile survival up -d --build
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
`SURVIVAL_WORLD_SEED=18273`. O cliente deve ser aberto normalmente: escolha
`Conectar ao servidor` e informe somente o IP ou dominio e a porta. O servidor
envia a seed e o modo procedural durante a conexao.

Para iniciar o modo sobrevivencia no servidor dedicado, use:

```bash
docker compose --profile survival up -d --build
```
