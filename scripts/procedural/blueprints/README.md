# Blueprints

Contem apenas dados estruturais da cidade procedural. Nenhum arquivo deste
diretorio instancia meshes ou acessa a cena ativa.

- `room_blueprint.gd`: comodo, portas e janelas.
- `unit_blueprint.gd`: apartamento ou unidade independente, com consulta de comodo por ponto, escala por eixo, espelhamento e remocao de janelas por parede.
- `floor_blueprint.gd`: unidades reutilizadas em um andar.
- `building_blueprint.gd`: edificio, andares, lances de escada, passagens entre unidades e terraco no topo.
- `road_blueprint.gd`: segmento da malha viaria.
- `lot_blueprint.gd`: terreno, orientacao para a rua e edificio selecionado.
- `block_blueprint.gd`: quarteirao e seus lotes.
- `city_blueprint.gd`: cidade completa.
