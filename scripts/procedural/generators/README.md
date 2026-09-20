# Generators

Os geradores recebem seeds e retornam somente blueprints. Eles nao criam nodes,
meshes ou colisoes.

- `room_generator.gd`: layouts residenciais (sala e cozinha distribuindo os comodos), comerciais, de lobby e do nucleo da escada com passagens acessiveis. Com a flag `use_plan_layout` (ligada) a unidade sai do `floor_plan_generator` (treemap + portas por arvore), variando por seed; `generate_apartment_from_plan(..., include_utility)` empurra sala e despensa para a borda (entradas principal e de servico); `store_layout_for_seed`/`generate_store` variam a entrada e o estoque/escritorio das lojas; desligue para voltar as duas plantas fixas.
- `building_generator.gd`: casas (media 16x13 ou grande 18x15 por seed, com o programa de comodos crescendo com a area e 2 entradas: principal na sala e de servico na despensa). Tambem gera predios com 1, 2 ou 4 apartamentos por andar (planta vinda do `floor_plan_generator`, entao cada apartamento varia por seed), corredor quando ha mais de um, terreo com recepcao/lixo/estoque e lances alternados ate o terraco.
- `city_generator.gd`: ruas curvas deterministicas, quarteiroes, lotes, fachadas orientadas para a rua e selecao de edificios.
- `lot_feasibility.gd`: pontua area, frentes de rua, declive e distrito para escolher por peso o arquetipo de cada lote, no lugar do sorteio seco.
