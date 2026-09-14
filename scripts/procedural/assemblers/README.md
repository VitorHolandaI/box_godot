# Assemblers

Os assemblers sao a unica parte que transforma blueprints em Nodes 3D. O MVP
usa `BoxMesh` e `BoxShape3D` para provar escala, portas, janelas, andares e
interiores antes de trocar a aparencia pelos assets finais.

- `building_assembler.gd`: monta casas com telhado, paredes internas, portas, moveis por comodo, luzes e apartamentos.
- `city_assembler.gd`: monta ruas diagonais, lotes sem bases artificiais e edificios e configura recorte por limites e andar.
