# Assemblers

Os assemblers sao a unica parte que transforma blueprints em Nodes 3D. O MVP
usa `BoxMesh` e `BoxShape3D` para provar escala, portas, janelas, andares e
interiores antes de trocar a aparencia pelos assets finais.

- `building_assembler.gd`: monta casas, apartamentos, comodos e paredes.
- `city_assembler.gd`: monta ruas, quarteiroes, lotes e edificios.
