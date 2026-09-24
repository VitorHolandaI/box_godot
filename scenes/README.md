# Cenas

Cenas reutilizaveis e composicao principal do jogo.

- `ammo_pickup.tscn`: caixa de municao militar coletavel com luz e animacao de flutuacao.
- `benchmark_indoor_escape.tscn`: cena headless que mede custo e taxa de fuga de zumbis presos dentro de casas procedurais.
- `benchmark_zombies.tscn`: cena dedicada para execucao headless de benchmark de estresse de zumbis, RAM e CPU.
- `building.tscn`: apartamento solido com shader de recorte.
- `bullet.tscn`: projetil visual e autoritativo com trajetoria fixa apos o disparo.
- `bush.tscn`: arbusto verde para floresta e ruinas.
- `car.tscn`: carro voxel decorativo.
- `drivable_car.tscn`: carro dirigivel (chassi `VehicleBody3D`, 4 `VehicleWheel3D`, assento, ponto de saida e `RunOverArea`); o modelo e o jipe CC0 `assets/models/jeep/pickup_armored.glb`, montado por `scripts/drivable_car.gd`.
- `grass_tuft.tscn`: tufo de grama decorativo.
- `in_game_menu.tscn`: menu sobreposto durante a partida (continuar, destravar personagem, menu principal, sair).
- `main.tscn`: mundo sem zumbis autorados nas ruas; entidades surgem pela politica da partida.
- `menu.tscn`: menu inicial, multiplayer e configuracoes.
- `player.tscn`: personagem militar jogavel com colisao que contem o modelo visual.
- `rock.tscn`: rocha/entulho para floresta e ruinas.
- `solid_venue.tscn`: base configuravel para casas e estabelecimentos.
- `streetlight.tscn`: poste de iluminacao decorativo.
- `wave_supply_pickup.tscn`: ponto de vida ou municao renovado pelas ondas de sobrevivencia.
- `test_combat_and_variants.tscn`: runner headless para combate, trajetoria, safehouse, hordas e populacao de zumbis.
- `tree.tscn`: arvore larga com copa em blocos.
- `tree_araucaria.tscn`: araucaria colunar com camadas horizontais.
- `tree_dead.tscn`: arvore seca com galhos aparentes.
- `tree_ipe.tscn`: arvore florida com copa rosa.
- `tree_pine.tscn`: pinheiro alto com tres niveis de copa.
- `tree_sequoia.tscn`: sequoia alta com copa conica em camadas.
- `zombie.tscn`: inimigo voxel com vida, membros animados e colisao que contem o modelo visual.
- `zombie_ragdoll.tscn`: ragdoll articulado com pescoco fisicamente limitado.
