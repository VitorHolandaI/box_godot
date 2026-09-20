# Assemblers

Os assemblers sao a unica parte que transforma blueprints em Nodes 3D. O MVP
usa `BoxMesh` e `BoxShape3D` para provar escala, portas, janelas, andares e
interiores antes de trocar a aparencia pelos assets finais.

- `building_materials.gd`: fabrica de materiais opacos e de vidro com visibilidade por andar.
- `mesh_batcher.gd`: funde as caixas estaticas de cada edificio num unico no por material para cortar draw calls.
- `box_builder.gd`: caixa visual com colisao opcional compartilhada pelos assemblers.
- `building_assembler.gd`: monta casas com telhado, paredes internas, portas com nome deterministico, moveis por comodo (cama, geladeira, fogao, quadro e banheiro), ar-condicionado externo, luzes, apartamentos, o navmesh do edificio e ancoras de loot internas (grupo `building_loot_points`) usadas para espalhar municao/arma dentro dos predios. Cada trecho de parede vira um `WallEdge` (eixo, linha, pedaco coberto, origem e piso), e o desenho e feito em tres passos: vaos de porta, vaos de janela que nao batem em porta, e os paineis pintados em volta.
- `commercial_detail_assembler.gd`: fachada, placa, ATM, caixa e mobiliario visual de loja, mercado e loja de armas, respeitando a zona de descompressao da entrada e a posicao da porta definida por `store_layout_for_seed`.
- `apartment_detail_assembler.gd`: balcao da recepcao (com caixa de correio, banco, maquina de venda e plantas), lixeiras do lixo, split de ar-condicionado nos apartamentos e condensadoras na fachada do predio.
- `roof_terrace_assembler.gd`: terraco no topo dos predios com laje vazada pelo ultimo lance, mureta e casinha da escada.
- `house_roof_assembler.gd`: telhado de duas aguas a 30 graus com empenas fechadas, cumeeira, testeiras, cor de telha e chamine.
- `street_light_assembler.gd`: postes em escala real ao longo das ruas procedurais, fora de lotes e do asfalto.
- `stair_assembler.gd`: lajes com vao, lances alternados, rampa de colisao alinhada a laje e guarda-corpos.
- `city_assembler.gd`: monta ruas diagonais, lotes sem bases artificiais e edificios e configura recorte por limites e andar.
