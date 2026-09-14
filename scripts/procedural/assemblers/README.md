# Assemblers

Os assemblers sao a unica parte que transforma blueprints em Nodes 3D. O MVP
usa `BoxMesh` e `BoxShape3D` para provar escala, portas, janelas, andares e
interiores antes de trocar a aparencia pelos assets finais.

- `building_materials.gd`: fabrica de materiais opacos e de vidro com visibilidade por andar.
- `mesh_batcher.gd`: funde as caixas estaticas de cada edificio num unico no por material para cortar draw calls.
- `box_builder.gd`: caixa visual com colisao opcional compartilhada pelos assemblers.
- `building_assembler.gd`: monta casas com telhado, paredes internas, portas com nome deterministico, moveis por comodo, luzes, apartamentos e o navmesh do edificio.
- `house_roof_assembler.gd`: telhado de duas aguas a 30 graus com empenas fechadas, cumeeira, testeiras, cor de telha e chamine.
- `street_light_assembler.gd`: postes em escala real ao longo das ruas procedurais, fora de lotes e do asfalto.
- `stair_assembler.gd`: lajes com vao, lances alternados, rampa de colisao alinhada a laje e guarda-corpos.
- `city_assembler.gd`: monta ruas diagonais, lotes sem bases artificiais e edificios e configura recorte por limites e andar.
