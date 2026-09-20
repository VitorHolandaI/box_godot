# Addons

Addons de terceiros usados pelo projeto. Nada aqui e codigo do jogo.

- `gdscript-linter/`: analise estatica de GDScript (qualidade, divida tecnica e
  complexidade) do projeto [godot-gdscript-linter](https://github.com/graydwarf/godot-gdscript-linter),
  autor Poplava, licenca MIT (ver `gdscript-linter/LICENSE` e
  `gdscript-linter/THIRD_PARTY_LICENSES.txt`).

## Uso

O linter roda de duas formas, sem alterar nenhum arquivo do jogo:

- Dock no editor: habilite em Project > Project Settings > Plugins >
  "GDScript Linter - Static Code Quality Analyzer". Le `.gdlint.cfg`.
- CLI/CI: `scripts/lint_gdscript.sh` (le `gdlint.json`). Nao precisa habilitar
  o plugin.

Os limites de `.gdlint.cfg` e `gdlint.json` seguem o AGENTS.md do projeto
(funcao ate 80 linhas, arquivo ate 500, no maximo 2 niveis de indentacao).
Mantenha os dois em sincronia: o editor le o `.cfg`, o CLI le o `.json`.
