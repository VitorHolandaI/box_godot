#!/usr/bin/env bash
# Exporta clientes release para Linux e Windows e seus checksums.
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

restore_presets() {
	cp "$presets_backup" "$presets_file"
}
trap restore_presets EXIT

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

mkdir -p "$dist_dir"
godot --headless --path "$project_dir" --export-release Linux "$dist_dir/box-godot-linux.x86_64"
godot --headless --path "$project_dir" --export-release Windows "$dist_dir/box-godot-windows.exe"
chmod +x "$dist_dir/box-godot-linux.x86_64"

cd "$dist_dir"
sha256sum box-godot-linux.x86_64 box-godot-windows.exe > SHA256SUMS
printf '%s\n' "Exports disponiveis em $dist_dir"
