# Assemblers

Os assemblers sao a unica parte que transforma blueprints em Nodes 3D. O MVP
usa `BoxMesh` e `BoxShape3D` para provar escala, portas, janelas, andares e
interiores antes de trocar a aparencia pelos assets finais.

- `building_materials.gd`: fabrica de materiais opacos e de vidro com visibilidade por andar.
- `box_builder.gd`: caixa visual com colisao opcional compartilhada pelos assemblers.
- `building_assembler.gd`: monta casas com telhado, paredes internas, portas com nome deterministico, moveis por comodo, luzes, apartamentos e o navmesh do edificio.
- `stair_assembler.gd`: lajes com vao, lances alternados, rampa de colisao alinhada a laje e guarda-corpos.
- `city_assembler.gd`: monta ruas diagonais, lotes sem bases artificiais e edificios e configura recorte por limites e andar.
