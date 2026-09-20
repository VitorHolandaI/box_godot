# Shaders

Materiais customizados usados pelo mundo 3D.

- `building_cutout.gdshader` (detalhe procedural de fachada: grao, sujeira que sobe da rua, junta de andar, modulo vertical e fiada de telha nos telhados; `detail_strength=0` volta a cor chapada): material opaco de edificio; na rua abre o recorte ate o jogador e, dentro, mostra so o andar atual com paredes cortadas a meia altura e tampa escura.
- `building_glass.gdshader`: vidro translucido de janela com a mesma regra de andares.
- `building_visibility.gdshaderinc`: regras compartilhadas de andar atual, corte de secao, tubo da camera e passe de sombra (uniform global `interior_focus_position`).
- `car_rust.gdshader`: ferrugem, desbotamento e queimaduras procedurais em veiculos abandonados.
- `street_asphalt.gdshader`: asfalto procedural da rua (grao, remendo de manutencao, trinca, sarjeta escura na borda e faixa central amarela tracejada e gasta). Sem textura de arquivo: tudo em espaco de mundo, porque a rua e feita de caixas sem UV util.
- `zombie_dissolve.gdshader`: desintegracao em graos de voxel com borda de cinza, controlada por instancia.
- `ground_dirt.gdshader`: terra texturizada procedural para o solo do mapa.
