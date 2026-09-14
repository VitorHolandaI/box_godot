#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$project_dir/dist"

mkdir -p "$dist_dir"
godot --headless --path "$project_dir" --export-release Linux "$dist_dir/box-godot-linux.x86_64"
godot --headless --path "$project_dir" --export-release Windows "$dist_dir/box-godot-windows.exe"
chmod +x "$dist_dir/box-godot-linux.x86_64"

cd "$dist_dir"
# Pacotes para download: o executavel com PCK embutido comprime para ~40% (77 MB -> 31 MB no Linux).
# -FS sincroniza um zip existente com o arquivo atual, sem apagar nada antes.
zip -q -9 -FS box-godot-linux.zip box-godot-linux.x86_64
zip -q -9 -FS box-godot-windows.zip box-godot-windows.exe
sha256sum box-godot-linux.x86_64 box-godot-windows.exe box-godot-linux.zip box-godot-windows.zip > SHA256SUMS
printf '%s\n' "Exports disponiveis em $dist_dir"
