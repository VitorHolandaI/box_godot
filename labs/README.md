# labs

Cenas de teste **visíveis**: cada uma isola uma parte do jogo numa janela para
olhar com o olho, sem subir partida, servidor ou cidade inteira. É a metade
assistível dos testes de `scripts/test_*.gd`, que rodam headless e só dizem
PASS ou FALHA. Quando um teste headless afirma um número, o lab correspondente
mostra esse número na tela para dar para conferir.

Nada aqui entra na partida de verdade. O jogo real sobe por `scenes/main.tscn`.

## Arquivos

- `controle_lab.gd` + `controle_lab.tscn`: campo de provas do controle. Força o
  jogador 1 no primeiro controle plugado (ou num controle simulado quando não
  há nenhum), pendura o `gamepad_readout.gd` na raiz e troca para
  `scenes/main.tscn`. Como é a partida de verdade, dá para testar pelo controle
  tudo que o boneco faz: andar, mirar, atirar em zumbi, entrar e dirigir o
  carro, abrir porta e pegar arma do chão. Roda com
  `godot --path . labs/controle_lab.tscn`.
- `gamepad_readout.gd`: o painel que o `controle_lab` pendura por cima da
  partida. Mostra ao vivo o eixo cru de `GameConfig.player_look_axis`, o mesmo
  eixo depois da zona morta de `PlayerCharacter.look_stick_vector`, o cursor
  virtual, o `move_input` do boneco e uma marca por ação do controle. São os
  mesmos valores que `scripts/test_gamepad_aim.gd` confere sem janela. Sem
  controle plugado ele liga um roteiro que simula os dois analógicos e os
  botões com `Input.parse_input_event`, do mesmo jeito que o teste faz. TAB
  alterna simulado/controle plugado, ESPAÇO segura o gatilho direito.
- `zombie_lab.gd` + `zumbi_lab.tscn`: cena das variantes de zumbi. O player é
  dirigido pelo `PlayerBotAI` e cada zumbi simula sozinho. `[` `]` escolhem a
  variante, `-` `=` a quantidade, `K` spawna vivos, `N` cadáveres, `O` mata a
  variante escolhida, `L` mata todos, `M` limpa, `G` liga o modo deus do
  player. `--lab-coletor` monta a demo do coletor; aceita `--lab-variant=NN`,
  `--lab-spawn=N` e `--lab-corpse=N` (usado também no teste headless do
  coletor).
- `casa_lab.gd` + `casas_lab.tscn`: uma construção por vez (casa, loja, mercado
  ou prédio) gerada pelo mesmo caminho da cidade procedural
  (`building_generator` -> `ProceduralCityAssembler`). `G` regenera com outra
  seed, `[` `]` trocam o tipo. Aceita `--lab-seed=NNNNN`, `--lab-kind=house` e
  `--lab-voo` (troca para a câmera de voo).
- `carro_lab.gd` + `carro_lab.tscn`: mapa vazio com chão texturizado, sol e um
  jipe dirigido por bot. `--sem-bot` deixa o jipe parado.
  `scripts/test_drivable_car.gd` carrega esta cena no teste headless do carro.

## Quem depende de quem

Os labs consomem o jogo, o jogo nunca consome os labs. Eles instanciam
`scenes/player.tscn`, `scenes/zombie.tscn`, `scenes/drivable_car.tscn` e os
autoloads (`GameConfig`, `NetworkSession`), e o `controle_lab` ainda troca para
`scenes/main.tscn`. A única seta na volta é `scripts/test_drivable_car.gd`, que
usa `carro_lab.tscn` como cenário pronto do teste headless.
