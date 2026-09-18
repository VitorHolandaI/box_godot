#!/usr/bin/env bash
# Exporta clientes release para Linux, Windows e macOS e seus checksums.
# O macOS usa o template universal oficial, que nao vem no pacote enxuto do
# projeto: baixe so ele com scripts/fetch_macos_template.py (o .tpz inteiro tem
# >1 GB). Sem o template, o macOS e pulado com aviso.
# Templates customizados (scripts/build_custom_templates.sh) sao opcionais:
#   LINUX_TEMPLATE=~/tinker_git/godot-4.7.2-src/bin/godot.linuxbsd.template_release.x86_64 \
#   WINDOWS_TEMPLATE=~/tinker_git/godot-4.7.2-src/bin/godot.windows.template_release.x86_64.exe \
#   scripts/build_exports.sh
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# DIST_DIR permite exportar sem sobrescrever o dist/ de um cliente aberto.
dist_dir="${DIST_DIR:-$project_dir/dist}"
presets_file="$project_dir/export_presets.cfg"
presets_backup="$(mktemp)"
cp "$presets_file" "$presets_backup"
build_info_file="$project_dir/scripts/build_info.gd"
build_info_backup="$(mktemp)"
cp "$build_info_file" "$build_info_backup"

restore_presets() {
	cp "$presets_backup" "$presets_file"
	cp "$build_info_backup" "$build_info_file"
}
trap restore_presets EXIT

# Grava commit/timestamp no BuildInfo antes do export (o binario imprime quem
# ele e e o servidor recusa cliente de build diferente: senao o input e
# recusado sem explicacao e o jogador nao anda). Restaurado no fim pelo trap.
write_build_info() {
	local commit
	commit="$(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || echo desconhecido)"
	if [[ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]]; then
		commit="${commit}+sujo"
	fi
	local built_at
	built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	COMMIT_VALUE="$commit" BUILT_AT_VALUE="$built_at" BUILD_INFO_PATH="$build_info_file" python3 - <<'INNERPY'
import os
path = os.environ["BUILD_INFO_PATH"]
commit = os.environ["COMMIT_VALUE"]
built_at = os.environ["BUILT_AT_VALUE"]
lines = open(path).read().split("\n")
for index, line in enumerate(lines):
    if line.startswith("const COMMIT :="):
        lines[index] = 'const COMMIT := "%s"' % commit
    elif line.startswith("const BUILT_AT :="):
        lines[index] = 'const BUILT_AT := "%s"' % built_at
open(path, "w").write("\n".join(lines))
INNERPY
	printf '%s\n' "BuildInfo do export: commit=$commit em $built_at"
}

# Os caminhos de template sao da maquina de build; o preset versionado fica vazio
# e so recebe o caminho durante o export.
set_release_template() {
	local preset_index="$1"
	local template_path="$2"
	if [[ -z "$template_path" ]]; then
		return
	fi
	if [[ ! -f "$template_path" ]]; then
		printf 'Falha: template "%s" nao existe; esperado arquivo gerado por build_custom_templates.sh.\n' "$template_path" >&2
		exit 1
	fi
	python3 - "$presets_file" "$preset_index" "$template_path" <<'PY'
import sys
path, index, template = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split("\n")
section = f"[preset.{index}.options]"
inside = False
for i, line in enumerate(lines):
    if line.startswith("["):
        inside = line == section
    elif inside and line.startswith("custom_template/release="):
        lines[i] = f'custom_template/release="{template}"'
open(path, "w").write("\n".join(lines))
PY
	printf 'Usando template customizado no preset %s: %s\n' "$preset_index" "$template_path"
}

set_release_template 0 "${LINUX_TEMPLATE:-}"
set_release_template 1 "${WINDOWS_TEMPLATE:-}"
set_release_template 2 "${MACOS_TEMPLATE:-}"
write_build_info

mkdir -p "$dist_dir"
godot --headless --path "$project_dir" --export-release Linux "$dist_dir/box-godot-linux.x86_64"
godot --headless --path "$project_dir" --export-release Windows "$dist_dir/box-godot-windows.exe"
chmod +x "$dist_dir/box-godot-linux.x86_64"

# macOS so quando o template universal estiver instalado (ver o cabecalho).
macos_template="$HOME/.local/share/godot/export_templates/4.7.2.stable/macos.zip"
exported_files=(box-godot-linux.x86_64 box-godot-windows.exe)
if [[ -f "$macos_template" ]]; then
	godot --headless --path "$project_dir" --export-release macOS "$dist_dir/box-godot-macos.zip"
	exported_files+=(box-godot-macos.zip)
else
	printf 'aviso: template de macOS ausente (%s); pulando o macOS.\n' "$macos_template" >&2
	printf '       baixe com: python3 scripts/fetch_macos_template.py\n' >&2
fi

cd "$dist_dir"
sha256sum "${exported_files[@]}" > SHA256SUMS
printf '%s\n' "Exports disponiveis em $dist_dir"
