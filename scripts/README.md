# Scripts

Logica de jogo, rede, interface e testes automatizados.

- `ammo_pickup.gd`: caixa de municao militar coletavel, recarga de reserva e sincronizacao de rede.
- `benchmark_zombies.gd`: suite de estresse e perfilamento de consumo de RAM (Heap e RSS SO), tempo de CPU de fisica e capacidade maxima de zumbis do servidor.
- `benchmark_zombies.sh`: script de execucao automatizada do benchmark de zumbis em modo headless.
- `building.gd`: cor individual dos apartamentos.
- `building_assembler_3d.gd`: montador procedural de lotes e edificios com muros perimetrais, rampas de garagem subterranea, cercas, toldos e props urbanos.
- `bullet.gd`: movimento, impacto e dano dos projeteis com mascara para fogo amigo e exclusao do atirador.
- `city_generator.gd`: geracao deterministica de ruas, calcadas urbanas de concreto (sem terra marrom sob predios), veiculos oxidados/queimados e muralhas.
- `game_config.gd`: controles e preferencias graficas persistentes.
- `in_game_menu.gd`: pausa local e navegacao durante a partida.
- `local_camera.gd`: acompanhamento de um jogador pela camera local.
- `main.gd`: ciclo da partida, spawns, snapshots e bot de teste.
- `menu.gd`: configuracao de jogadores, conexao e opcoes graficas.
- `modular_building_builder.gd`: gerador de predios procedurais com andares multiplos andaveis, escadas reais transitaveis, sacadas, terraco caminhavel, iluminacao e materiais de dois tons.
- `network_session.gd`: sessao ENet, roster, handshake de carregamento e suporte a modo de teste unitario.
- `performance_hud.gd`: HUD de FPS, draw calls, objetos e memoria (alterna com F3).
- `player.gd`: personagem jogavel militar com sistema de 3 vidas maximas, renascimento na Safehouse, armas com fogo amigo e sincronizacao em rede.
- `player_animator.gd`: gerenciador procedural de poses, marcha e animacao expressiva de impacto/flinch.
- `player_bot_ai.gd`: IA de jogadores bots (patrulha, combate tatico, evasao de obstaculos e suporte a testes).
- `run_4_bots.sh`: inicializa servidor dedicado e abre 4 janelas com bots jogando sozinhos em grade 2x2.
- `safehouse_builder.gd`: gerador procedural da Safehouse fortificada de 2 andares com estacoes de respawn, escadaria real transitavel, caixas de municao, sacada de franco-atirador e iluminacao de refugio.
- `solid_venue.gd`: construcao oca (piso, paredes e porta) e colisao de casas, lojas e apartamentos.
- `split_screen_manager.gd`: viewports, cameras e HUDs locais com exibicao de vidas restantes por jogador.
- `test_combat_and_variants.gd`: suite de testes unitarios de combate, fogo amigo, flinch, 9 variantes anatomicas, 3 vidas, safehouse e propagacao sonora de tiros.
- `test_container.sh`: smoke test do servidor Docker.
- `test_dedicated.sh`: smoke test do servidor Godot nativo executando testes unitarios e teste com bot.
- `zombie.gd`: IA de zumbi com ecolocalizacao de tiros com atenuacao por distancia, investigacao em marcha lenta, sentidos, combate, knockback por dano e variantes anatomicas.
- `zombie_flock_coordinator.gd`: coordenador de hordas com algoritmo de Boids (separacao, alinhamento e coesao), lideres de cluster e LOD de fisica/sentidos.
- `zombie_mutator.gd`: configurador procedural de 9 variantes anatomicas (pedaco de braco, sem 1 braco, pedaco de perna, sem 1 perna, cabeca pela metade com cerebro exposto, rastejante, manco, corredor e classico) e animacoes de marcha e flinch.
- `zombie_ragdoll.gd`: fisica de ragdoll articulado com suporte a amputacoes e deformacoes correspondentes a cada uma das 9 variantes.
