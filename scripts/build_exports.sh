#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$project_dir/dist"

mkdir -p "$dist_dir"
godot --headless --path "$project_dir" --export-release Linux "$dist_dir/box-godot-linux.x86_64"
godot --headless --path "$project_dir" --export-release Windows "$dist_dir/box-godot-windows.exe"
chmod +x "$dist_dir/box-godot-linux.x86_64"

cd "$dist_dir"
sha256sum box-godot-linux.x86_64 box-godot-windows.exe > SHA256SUMS
printf '%s\n' "Exports disponiveis em $dist_dir"
