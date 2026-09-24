#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Compila templates release do Godot otimizados para tamanho, so com o que o
# box_godot usa (renderer gl_compatibility, Jolt/fisica 3D, CSG, glTF importado,
# ENet, navegacao 3D). Templates oficiais trazem Vulkan/D3D12/XR/video/audio
# comprimido e ocupam ~71 MB (Linux) / ~105 MB (Windows) dos executaveis.
#
# Uso:
#   GODOT_SRC=~/tinker_git/godot-4.7.2-src scripts/build_custom_templates.sh linux
#   GODOT_SRC=~/tinker_git/godot-4.7.2-src scripts/build_custom_templates.sh windows   # requer mingw-w64-gcc
set -euo pipefail

target="${1:-linux}"
godot_src="${GODOT_SRC:?defina GODOT_SRC com o caminho do codigo-fonte do Godot 4.7.2}"
scons_bin="${SCONS:-$godot_src/.venv-scons/bin/scons}"
jobs="${JOBS:-$(nproc)}"

size_flags=(
	target=template_release production=yes optimize=size debug_symbols=no
	vulkan=no d3d12=no use_volk=no disable_xr=yes accesskit=no
	module_openxr_enabled=no module_mobile_vr_enabled=no module_webxr_enabled=no
	module_camera_enabled=no module_theora_enabled=no module_vorbis_enabled=no
	module_ogg_enabled=no module_mp3_enabled=no module_interactive_music_enabled=no
	module_webrtc_enabled=no module_websocket_enabled=no module_jsonrpc_enabled=no
	module_upnp_enabled=no module_text_server_adv_enabled=no module_text_server_fb_enabled=yes
	module_gridmap_enabled=no module_lightmapper_rd_enabled=no module_raycast_enabled=no
	module_navigation_2d_enabled=no module_fbx_enabled=no module_msdfgen_enabled=no
	module_visual_shader_enabled=no module_objectdb_profiler_enabled=no
	module_basis_universal_enabled=no module_ktx_enabled=no module_tinyexr_enabled=no
	module_hdr_enabled=no module_tga_enabled=no module_bmp_enabled=no module_jpg_enabled=no
	module_dds_enabled=no module_noise_enabled=no module_vhacd_enabled=no
	module_xatlas_unwrap_enabled=no module_meshoptimizer_enabled=no
)

case "$target" in
	linux)
		platform_flags=(platform=linuxbsd arch=x86_64 speechd=no lto="${LTO:-full}")
		expected_binary="bin/godot.linuxbsd.template_release.x86_64"
		;;
	windows)
		if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
			printf '%s\n' "Falha: x86_64-w64-mingw32-gcc nao encontrado; instale mingw-w64-gcc." >&2
			exit 1
		fi
		# LTO desligado por padrao: o mingw-w64-gcc 16.2 quebra no link com
		# "internal compiler error: in binds_to_current_def_p, at symtab.cc:2611".
		platform_flags=(platform=windows arch=x86_64 use_mingw=yes lto="${LTO:-none}")
		expected_binary="bin/godot.windows.template_release.x86_64.exe"
		;;
	*)
		printf 'Falha: alvo invalido "%s"; esperado linux ou windows.\n' "$target" >&2
		exit 2
		;;
esac

cd "$godot_src"
"$scons_bin" -j"$jobs" "${platform_flags[@]}" "${size_flags[@]}"
if [[ ! -f "$expected_binary" ]]; then
	printf 'Falha: scons terminou sem gerar "%s".\n' "$godot_src/$expected_binary" >&2
	exit 1
fi
ls -la "$expected_binary"
