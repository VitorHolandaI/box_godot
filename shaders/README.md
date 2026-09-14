# Shaders

Materiais customizados usados pelo mundo 3D.

- `building_cutout.gdshader`: material opaco de edificio; na rua abre o recorte ate o jogador e, dentro, mostra so o andar atual com paredes cortadas a meia altura e tampa escura.
- `building_glass.gdshader`: vidro translucido de janela com a mesma regra de andares.
- `building_visibility.gdshaderinc`: regras compartilhadas de andar atual, corte de secao, tubo da camera e passe de sombra (uniform global `interior_focus_position`).
- `car_rust.gdshader`: ferrugem, desbotamento e queimaduras procedurais em veiculos abandonados.
- `zombie_dissolve.gdshader`: desintegracao em graos de voxel com borda de cinza, controlada por instancia.
- `ground_dirt.gdshader`: terra texturizada procedural para o solo do mapa.
