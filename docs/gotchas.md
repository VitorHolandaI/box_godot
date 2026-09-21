# Gotchas e aprendizados

Coisas que ja morderam neste projeto e a regra que evita repetir. Cada item tem
**sintoma -> causa -> regra**. Fonte: paginas do namespace `gotchas/` do
ai-memory, decisoes correlatas e as sessoes no repo. Doc vivo: ao descobrir um
gotcha novo, adicione aqui.

## Rede e build

### 1. Mudar a superficie de RPC sem subir o build -> cliente conecta e "nao anda"
- **Sintoma:** cliente antigo conecta, o servidor rejeita o input
  (`_submit_inputs: Method expected 1 argument(s), but called with 4`) e na tela
  e "nao consigo me mover".
- **Causa:** `GAME_BUILD` e a identidade do build e nao foi bumpado junto com a
  mudanca de `@rpc`.
- **Regra:** toda mudanca de `@rpc` exige subir `BuildInfo.GAME_BUILD`
  (`scripts/build_info.gd`) **e** atualizar `RPC_SIGNATURE` em
  `scripts/test_build_info.gd` (o teste falha de proposito se nao atualizar).
- Fonte: `gotchas/build-identity-and-rpc-surface.md`.

### 2. Comparar o commit do build nao serve na VPS
- **Sintoma:** o handshake recusaria um par que funciona.
- **Causa:** a VPS roda do fonte (`godot --headless --editor`), entao
  `BuildInfo.COMMIT` e sempre `"dev"`; o cliente e export com commit injetado.
- **Regra:** comparar build declarado + versao, nunca commit.

### 3. Sync de arma no chao e por NOME, nunca por indice
- **Sintoma:** arma errada aparecia no chao entre cliente e servidor.
- **Causa:** `SupplyNetworkState` usa indice e quebraria com reordenacao.
- **Regra:** sincronizar por nome (`ground_weapon_sync.gd`, campo no snapshot de
  jogadores).
- Fonte: `decisions/crate-weapons-airdrop-variants.md`.

### 4. "Atirei e nao morreu"
- **Causa:** o servidor resolve o acerto contra a posicao **atual**, nao a que o
  atirador estava vendo (10 Hz de snapshot + interpolacao no cliente).
- **Regra/plano:** hit rewind (lag compensation) por etapas; ver
  `decisions/lag-compensation-subtick-plan.md` (proposto, nao implementado).

## Mira e tiro

### 5. A bala tem que sair do cano **e** bater no ponto do reticulo
- **Sintoma:** a bala nascia do torso/cabeca, ou saia torta; tambem "a bala some
  no ar".
- **Causa:** origem no torso/cabeca, direcao so horizontal, ou ponto de
  convergencia fixo (80 m) que a poucos metros ainda carrega o offset do cano.
- **Regra:** origem no cano (`_muzzle_origin()`), direcao do cano ate o ponto
  que o reticulo aponta (`_fps_target_point` faz o raycast do centro da tela).
  Assim acerta a cruz a qualquer distancia.
- Arquivos: `scripts/player.gd` (`_local_aim_direction`, `_fps_target_point`,
  `_muzzle_origin`, `_active_muzzle_node`).

### 6. Cliente mandar **direcao** calculada com o cano dele desvia a bala
- **Sintoma:** no multiplayer a bala nao vai onde o reticulo aponta (o cliente
  acerta local, mas o servidor atira torto).
- **Causa:** a pose do cano difere entre cliente e servidor; `aim_dir` era
  calculado no cliente e aplicado com o cano do servidor.
- **Regra:** mandar o **ponto** (`aim_point`) no pacote e o servidor calcular
  `(ponto - cano_do_servidor)`. `aim_dir`/horizontal ficam de fallback (bots).

### 7. Convergence + cobertura + projetil lento
- **Sintoma:** "as vezes desvia" (a camera enxerga por cima, mas o tiro para na
  quina) e alvo em movimento leva tempo.
- **Causa:** o raio do olho (alto) passa, o do cano (baixo) clipa cobertura; e a
  pistola e projetil a 16 m/s.
- **Regra (ainda pendente):** dano por hitscan saindo da camera, com o tracer
  visual saindo do cano. Ver o backlog de tracer.

## Carro

### 8. Corpo do carro sem a layer da barreira atravessa o limite
- **Sintoma:** o carro passa da barreira do mapa.
- **Causa:** `VehicleBody3D` com `collision_mask` default (1) e a barreira em
  `PLAYER_ONLY_BOUNDARY_LAYER = 16`.
- **Regra:** `scenes/drivable_car.tscn` usa `collision_mask = 17` (mundo +
  barreira). Zumbi fica de fora de proposito (dano por `RunOverArea`).

### 9. Interpolacao do carro: buffer por tempo, nao perseguir o alvo
- **Sintoma:** mini-teleportes no carro do cliente.
- **Causa:** aplicar `interpolate_with` direto no alvo a 60 Hz anda em degraus.
- **Regra:** guardar um buffer de transforms e interpolar por tempo de render
  com atraso (`PROXY_INTERP_DELAY = 0.12`), como o `SnapshotInterpBuffer` dos
  jogadores. Mesma ideia para qualquer proxy de rede.

### 10. Avatar remoto e `reads_local_input`
- **Sintoma:** cliente nao sai do carro; porta nao abre em 1a pessoa.
- **Causa:** o codigo checava `reads_local_input` e lia `Input` direto — no
  avatar remoto (servidor) isso nunca processava.
- **Regra:** na autoridade, use o input que veio da rede (`interact_pressed`,
  `aim_direction`); so o host le `Input` cru. Ver `_handle_vehicle_exit` e
  `_face_aim_or_movement` em `scripts/player.gd`.

### 11. `camera_yaw` nao viaja pela rede
- **Sintoma:** corpo do avatar remoto virado pro lado errado em FPS.
- **Causa:** so a mira (`aim_dir`/`aim_point`) viaja; `camera_yaw` nao.
- **Regra:** no avatar remoto, derivar o yaw do corpo da direcao de mira.

## Camera e render

### 12. Camada de render escondida fora do `cull_mask` padrao
- **Sintoma:** a cabeca do jogador sumia para **todas** as cameras (no split, o
  outro jogador via um boneco sem cabeca).
- **Causa:** `1 << 20` = layer **21**; o `cull_mask` padrao do Godot e `0xFFFFF`
  (layers 1..20), entao nenhuma camera renderizava.
- **Regra:** usar layer 20 (`1 << 19`) em `HEAD_RENDER_LAYER` e so a camera de
  1a pessoa excluir. Teste de regressao em `test_gameplay_regressions.gd`.

### 13. Shader de predio em caixa fina vira aureola
- **Sintoma:** vidro da vitrine com um halo azul.
- **Causa:** `building_glass.gdshader` usa `depth_draw_opaque` + `cull_disabled`
  e o `building_cutout` emite `EMISSION` azul na borda do cutout (`rim`).
- **Regra:** peca fina/de fora usa material simples
  (`ProceduralBuildingMaterials.storefront_glass()`); o shader de visibilidade
  por andar e para o interior do predio (e some sozinho quando o FPS desliga o
  cutout).

## GDScript

### 14. `is_connected` compara os argumentos atados do Callable
- **Sintoma:** handler dispara 2x (abate/dinheiro em dobro).
- **Causa:** `is_connected(_on_x)` (sem bind) nunca acha `_on_x.bind(player)`.
- **Regra:** montar o Callable atado uma vez e checar esse mesmo objeto
  (`PvpDeathWiring.connect_once`).
- Fonte: `gotchas/gdscript-traps-bound-callable-and-input-keys.md`.

### 15. Chaves do estado de input != nomes das acoes do `GameConfig`
- **Sintoma:** lista fixa de acoes envelhece e uma acao nova entra sem
  tratamento no freeze/clear.
- **Regra:** iterar as chaves do proprio estado e zerar todo booleano,
  preservando `aim`/`slot` e nao-booleanos (`PvpMatch.frozen_input`).

### 16. Inferencia de tipo do GDScript
- **Sintoma:** erro de compilacao "Cannot infer the type of X because the value
  doesn't have a set type".
- **Causa:** `:=` com expressao `Variant` (ex.: `dict.get(...)`, item de array
  literal, ternario).
- **Regra:** anotar o tipo ou converter (`var x: float = ...`, `float(side)`),
  e nao usar `any`/`Dict` (AGENTS.md). `-Basis` unario nao compila; atribuir a
  `var x: Transform3D = ...` em vez de `as`.

### 17. Acoes `player_N_*` nascem em runtime
- **Sintoma:** `InputMap action "player_1_*" doesn't exist` todo frame.
- **Causa:** `GameConfig.configure_local_players()` cria as acoes; sem menu, nao
  existem.
- **Regra:** em cena/probe fora do menu, chamar `configure_local_players`.

## Testes, headless e shell

### 18. Verificacao headless engana
- **Sintoma:** cenario/timer sai errado, ou a imagem do probe nao reflete o jogo.
- **Causa:** `--quit-after N` conta FRAMES de render; em headless sem vsync passa
  muito mais rapido que a fisica. E `--headless` nao renderiza: probes visuais
  precisam rodar com janela.
- **Regra:** `--fixed-fps 60 --quit-after N` para N frames = N/60 s de
  simulacao; probe visual roda sem `--headless`. Nao matar com `timeout`
  (SIGTERM) se for ler stdout com buffer.
- Fonte: `procedures/zumbi-lab-no-editor.md`.

### 19. `_ready` sobrescreve var setada antes do 1o frame
- **Sintoma:** um probe seta um campo logo apos `add_child` e o valor "volta".
- **Causa:** no `SceneTree._initialize`, o `_ready` do no roda depois do retorno,
  sobrescrevendo o valor.
- **Regra:** setar no primeiro `_process`, depois do `_ready`.

### 20. `pkill -f <padrao>` mata o proprio shell
- **Sintoma:** o comando trava/derruba a sessao.
- **Causa:** o padrao casa com a propria linha de comando do shell.
- **Regra:** matar por PID (`kill <pid>`) ou usar padrao que nao case consigo
  (`[g]odot`).

### 21. `EXIT=134` na suite e core dump de shutdown conhecido
- **Regra:** o resultado valido e `UNIT_TEST_PASS` no log; o 134 e pre-existente.

## Contexto que ja mordeu (referencia)

### 22. Navegacao de bots de PvP sem navmesh
- Nao existe navmesh no projeto; bots usam rota pelas ruas. Licao: recalcular
  "a primeira esquina nao alcancada" a cada tick faz o bot ir e voltar no limite
  do raio de chegada.
- Fonte: `gotchas/pvp-bot-navigation.md`.

### 23. Zumbi preso em predio
- **Causa real:** vetor de boids (`flock_separation_vector` x1.5) chegava a
  3-4 m/s e sobrepujava o movimento. Rota interna usa NavigationServer3D num
  mapa isolado por predio (assado das BoxShape3D sem portas).
- Fonte: `decisions/zombie-indoor-navigation.md`.

### 24. `_run_physics_tick` do zumbi: complexidade e CPU sao coisas diferentes
- Complexidade 64 e o sintoma de otimizacoes inline, nao a causa de lag. Medir
  com `FramePerfProbe` (`zombie_ai`, `zombie_proxy`) e `--benchmark-zombies`.
- Fonte: `gotchas/zombie-run-physics-tick-complexity.md`.
