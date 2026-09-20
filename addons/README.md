# Addons

Addons de terceiros usados pelo projeto. Nada aqui e codigo do jogo.

- `gdscript-linter/`: analise estatica de GDScript (qualidade, divida tecnica e
  complexidade) do projeto [godot-gdscript-linter](https://github.com/graydwarf/godot-gdscript-linter),
  autor Poplava, licenca MIT (ver `gdscript-linter/LICENSE` e
  `gdscript-linter/THIRD_PARTY_LICENSES.txt`).

## Correcao local

O addon so reconhecia `func ` como inicio de funcao, entao o corpo de cada
`static func` era contado dentro da funcao anterior: `pick_drop_position`
aparecia com complexidade 26 por causa das quatro estaticas abaixo dela, e as
proprias estaticas nunca eram checadas. A deteccao passou a aceitar as duas
formas em `analyzer/checkers/function-checker.gd`, `analyzer/checkers/unused-checker.gd`,
`analyzer/ignore-handler.gd` e `analyzer/strict-handler.gd`. Com isso o relatorio
subiu de 195 para 262 problemas: nao piorou nada, so parou de esconder.

## Uso

O linter roda de duas formas, sem alterar nenhum arquivo do jogo:

- Dock no editor: habilite em Project > Project Settings > Plugins >
  "GDScript Linter - Static Code Quality Analyzer". Le `.gdlint.cfg`.
- CLI/CI: `scripts/lint_gdscript.sh` (le `gdlint.json`). Nao precisa habilitar
  o plugin.

Os limites de `.gdlint.cfg` e `gdlint.json` seguem o AGENTS.md do projeto
(funcao ate 80 linhas, arquivo ate 500, no maximo 2 niveis de indentacao).
Mantenha os dois em sincronia: o editor le o `.cfg`, o CLI le o `.json`.
