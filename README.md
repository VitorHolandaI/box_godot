# Box Godot

Jogo de zumbis em Godot 4 com dois modos: **sobrevivência** (ondas de zumbis,
loot, safehouse) e **mata-mata PVP** (dois times, compra de armas, melhor de 3
rodadas). Roda em janela única ou tela dividida (até 4 jogadores locais), com
servidor dedicado e cliente para Linux, Windows e macOS.

Autor: Vitor Holanda.

## Imagens

![Sobrevivencia: horda cercando o jogador num cruzamento da cidade](docs/imagens/hero-horda.jpg)

Vista de cima durante o jogo, com o HUD (vidas, munição, abates, sonar) e o minimapa.

![Onda alta: variantes maiores e o cerco fechando](docs/imagens/horda-onda-alta.jpg)

Onda alta: o mix de zumbis muda, aparecem variantes maiores e o HUD mostra hora, onda e restantes.

![Ataque aereo marcado no chao, com a horda em volta](docs/imagens/aereo-na-horda.jpg)

Ataque aereo: o alvo e marcado no chao e as bombas caem em linha sobre a horda.

![Granada explodindo no meio da horda](docs/imagens/granada-na-horda.jpg)

Granada: uma sequencia de granadas no meio da horda (a explosao em area dura
 menos de um segundo, entao a serie e o que garante o flagra).

![Esquadrao SWAT ajudando a segurar a rua](docs/imagens/swat-aliado.jpg)

SWAT: um esquadrao aliado entra na rua e segura o cerco por 20 segundos.

![Aviao de suprimentos cruzando a cidade](docs/imagens/airdrop-aviao.jpg)

Airdrop: o aviao cruza baixo sobre as ruas e marca o ponto de soltura.

![Crate de armas descendo de paraquedas](docs/imagens/airdrop.jpg)

...e o crate de armas desce de paraquedas no ponto marcado.

![Sonar ativo revelando zumbis no minimapa](docs/imagens/sonar.jpg)

Sonar ativo: os zumbis por perto viram pontos no minimapa, inclusive atras de parede.

![Mata-mata PVP: tempo de compra na base](docs/imagens/pvp-freezetime.jpg)

Mata-mata PVP: tempo de compra na base, com o placar `Time A x Time B` no HUD.

![Fim de rodada no mata-mata](docs/imagens/pvp-fim-de-rodada.jpg)

Fim de rodada por eliminacao, com o placar atualizado.

![Tela dividida com 4 jogadores locais](docs/imagens/tela-dividida.jpg)

Tela dividida 2x2, com um HUD por jogador: ate 4 jogadores locais na mesma tela,
 cada um com seu dispositivo (teclado ou controle).

![Cidade procedural vista de cima](docs/imagens/cidade-ampla.jpg)

Cidade procedural: quadras, ruas, muralha e a borda da floresta.

As imagens sao geradas pelo proprio jogo (`scripts/capture_shots.sh`); todas em
[`docs/imagens/`](docs/imagens/).

## Requisitos

- Godot **4.7.2** (padrão do projeto; use a mesma versão para servidor e
  cliente)
- Docker com `docker compose` (servidor local/VPS)

## Como rodar

```bash
# editor (desenvolvimento)
godot --path . --editor

# cliente conectando num servidor (mesmo build do servidor)
godot --path . -- --join=127.0.0.1 --server-port=27015

# servidor dedicado direto pelo Godot (sobrevivência)
godot --headless --path . -- --server --server-port=27015 --survival

# servidor via Docker, escolhendo o modo na hora
scripts/server_menu.sh            # menu interativo
scripts/server_menu.sh pvp up     # mata-mata (sem bots)
scripts/server_menu.sh survival up
PVP_BOTS=4 scripts/server_menu.sh pvp up   # com 4 bots, para testar
```

Portas: **27015/udp** (jogo) e **27016/udp** (descoberta de salas na LAN). Não
abra TCP.

## Modos

- **Sobrevivência**: ondas progressivas até 600 zumbis vivos, safehouse com 3
  vidas por jogador, arma que desgasta e munição escassa.
- **Mata-mata PVP**: duas bases em cantos opostos, compra de arma só na fase de
  compra e dentro da própria base, sem respawn durante a rodada, melhor de 3.
  Munição abundante e arma sem durabilidade. Bots de teste opcionais.

## Controles

- `WASD`: movimentar
- `Espaco`: pular
- `Shift`: correr
- `1` / `2`: faca / pistola
- Clique esquerdo ou `F`: atacar
- `R`: recarregar
- `B`: menu de compra (só no PVP)
- `Esc`: menu da partida (pausa no local, continua no servidor)

No gamepad: analógico esquerdo move; `A` pula, `B` corre, `X` ataca, `LB`/`RB`
facas/pistola, `Y` recarrega. Cada jogador remapeia o próprio controle no menu.

## Estrutura

```
scripts/          lógica do jogo (rede, jogador, zumbis, cidade, PVP, testes)
scenes/           cenas e modelos
shaders/          shaders
compose.yaml      servidor dedicado em Docker
dist/             clientes exportados (gerados, não versionados)
docs/             documentação detalhada
```

## Documentação

- [`docs/`](docs/README.md) — índice da documentação
- [Cidade e mundo](docs/cidade-e-mundo.md)
- [Mecânicas](docs/mecanicas.md)
- [Multiplayer e servidor](docs/multiplayer.md)
- [Modo mata-mata (PVP)](docs/pvp.md)
- [Desenvolvimento, builds e testes](docs/desenvolvimento.md)

## Testes

```bash
godot --headless --path . -- --unit-test     # suite completa
bash scripts/test_dedicated.sh               # servidor dedicado + bot
bash scripts/test_container.sh               # container Docker
```

Detalhes em [`docs/desenvolvimento.md`](docs/desenvolvimento.md).
