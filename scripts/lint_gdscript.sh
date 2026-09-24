#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

# Analise estatica de qualidade do GDScript com o addon godot-gdscript-linter.
# Nao altera arquivos: so le e reporta.
#
# Uso:
#   scripts/lint_gdscript.sh                          # relatorio no console
#   scripts/lint_gdscript.sh --json                   # JSON para maquinas
#   scripts/lint_gdscript.sh --github                 # anotacoes no GitHub Actions
#   scripts/lint_gdscript.sh --html -o relatorio.html # relatorio HTML
#   scripts/lint_gdscript.sh --severity critical      # so criticos
#   scripts/lint_gdscript.sh --no-ignore              # ignora os gdlint:ignore
#
# Saida: 0 sem problemas, 1 so warnings, 2 ha criticos.
# Config: gdlint.json na raiz (o dock do editor usa .gdlint.cfg).

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
analyzer="res://addons/gdscript-linter/analyzer/analyze-cli.gd"

if [[ ! -f "$project_dir/addons/gdscript-linter/analyzer/analyze-cli.gd" ]]; then
	printf '%s\n' "Falha: addon gdscript-linter ausente em addons/gdscript-linter." >&2
	exit 3
fi

godot --headless --path "$project_dir" --script "$analyzer" -- "$@"
