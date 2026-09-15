# Generators

Os geradores recebem seeds e retornam somente blueprints. Eles nao criam nodes,
meshes ou colisoes.

- `room_generator.gd`: layouts residenciais (sala e cozinha distribuindo os comodos), comerciais, de lobby e do nucleo da escada com passagens acessiveis.
- `building_generator.gd`: casas ampliadas e predios com um apartamento grande por andar, nucleo de escada lateral, lances alternados ate o terraco e passagem pela sala.
- `city_generator.gd`: ruas curvas deterministicas, quarteiroes, lotes, fachadas orientadas para a rua e selecao de edificios.
