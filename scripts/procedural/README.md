# Procedural City MVP

Este diretorio separa a geracao logica de blueprints da montagem visual 3D.

- `blueprints/`: dados deterministas de ruas, lotes, edificios e interiores.
- `generators/`: transforma uma seed em blueprints validaveis.
- `assemblers/`: transforma blueprints em nos 3D com malhas e colisoes simples.
- `navigation/`: navmesh por edificio usado pela IA dos zumbis.

O fluxo demonstravel e ativado com `--procedural-city` e aceita `--world-seed=`.
