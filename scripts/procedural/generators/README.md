# Generators

Os geradores recebem seeds e retornam somente blueprints. Eles nao criam nodes,
meshes ou colisoes.

- `room_generator.gd`: layouts residenciais, comerciais, de lobby e do nucleo da escada com passagens acessiveis.
- `building_generator.gd`: arquétipos de casas e predios residenciais com nucleo de escada fixo, lances alternados e passagens entre apartamentos.
- `city_generator.gd`: ruas curvas deterministicas, quarteiroes, lotes, fachadas orientadas para a rua e selecao de edificios.
