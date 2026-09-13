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

O mapa procedural usa seed fixa para manter ruas e lotes iguais no servidor e
nos clientes. A grade inclui apartamentos, casas, lojas, mercados e shoppings
solidos, com cores e orientacoes variadas. O solo e terra texturizada procedural
e os arredores tem cara de apocalipse: uma muralha danificada cerca a area
jogavel, e um anel de ruinas, entulho e arvores secas separa a cidade da
floresta externa.

A floresta mistura arvores largas, pinheiros e arvores secas com arbustos,
rochas e tufos de grama. A opcao de qualidade grafica regula a densidade: 30
arvores por lado no baixo, 60 no medio e 100 no alto.

Zumbis surgem longe do jogador, na floresta, e caminham para dentro da cidade.
A muralha bloqueia os jogadores, mas os zumbis atravessam os vao quebrados. O
alvo global da partida e de 600 zumbis vivos: eles aparecem gradualmente e cada
morte libera uma vaga que tambem e reposta aos poucos, independentemente da
quantidade de jogadores.

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

O servidor usa ENet na porta `7000/udp` e executa a simulacao autoritativa sem
um jogador local. Para iniciar diretamente com o Godot instalado:

```bash
godot --headless --path . -- --server --server-port=7000
```

O menu do jogo oferece `Conectar ao servidor`; informe o IP ou dominio da VPS.
Cada computador pode solicitar de um a quatro jogadores locais, respeitando o
limite de quatro avatares na partida inteira.

Para construir e iniciar o container isolado:

```bash
docker compose up --build -d
docker compose logs -f game-server
```

Na VPS, publique somente `7000/udp` no firewall do sistema e no firewall do
provedor. O container roda como usuario sem privilegios, com filesystem somente
leitura, sem capabilities Linux e com limites de CPU, memoria e processos.

Para copiar apenas os arquivos de implantacao para a VPS:

```bash
rsync -av --exclude .git --exclude .godot --exclude .ai-memory.toml . usuario@vps:/srv/box-godot/
```

Depois, na VPS:

```bash
cd /srv/box-godot
docker compose up --build -d
```

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
ataque de zumbi replicado, projetil visual e a morte de um zumbi.
Entrada nao predeterminada e erros de script embarcam nesses smoke tests.
