#!/usr/bin/env bash
# Captura os frames de divulgacao (README/docs) pelo modo --capture do jogo.
#
# Uso:
#   scripts/capture_shots.sh                # todas as receitas
#   scripts/capture_shots.sh --shot=sonar   # uma receita
#   scripts/capture_shots.sh --list         # lista as receitas
#   scripts/capture_shots.sh --no-optimize  # so captura (nao gera docs/imagens)
#
# Cada receita roda uma instancia do jogo (windowed, 1920x1080 pelo content
# scale) que se posiciona sozinha e salva o PNG em dist/capturas/<receita>.png.
# O log de cada uma fica em dist/capturas/<receita>.log.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/dist/capturas"
IMG_DIR="$PROJECT_DIR/docs/imagens"
IMAGE_DIR_ZUMBIS="$PROJECT_DIR/docs/imagens/zumbis"
CAPTURE_TIMEOUT="${CAPTURE_TIMEOUT:-240}"
OPTIMIZE_WIDTH="${OPTIMIZE_WIDTH:-1600}"
OPTIMIZE_QUALITY="${OPTIMIZE_QUALITY:-82}"
RECIPES=(hero-horda horda-onda-alta cidade-ampla sonar tela-dividida aereo-na-horda granada-na-horda swat-aliado airdrop airdrop-aviao pvp-freezetime pvp-rodada pvp-fim-de-rodada)
GIF_DIR="$IMAGE_DIR_ZUMBIS"
# Uma receita por variante de zumbi (21 no enum de zombie_mutator.gd): elas so
# rodam com --gif ou --shot=zumbi-NN, nunca no lote normal (sao lentas).
GIF_RECIPES=()
for _index in $(seq -w 0 20); do GIF_RECIPES+=("zumbi-$_index"); done

# Wayland: a captura abre janela de verdade, entao precisa do display da sessao.
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

requested_shot=""
optimize=1

while [[ $# -gt 0 ]]; do
	case "$1" in
		--shot=*) requested_shot="${1#--shot=}" ;;
		--list)
			printf 'frames:\n'
			printf '  %s\n' "${RECIPES[@]}"
			printf 'gifs por variante (use --gif ou --shot=zumbi-NN):\n'
			printf '  %s\n' "${GIF_RECIPES[@]}"
			exit 0
			;;
		--gif)
			RECIPES=("${GIF_RECIPES[@]}")
			requested_shot="__gif__"
			;;
		--no-optimize) optimize=0 ;;
		--help|-h)
			sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "arg desconhecido: '$1' (use --shot=NOME, --list ou --no-optimize)" >&2
			exit 2
			;;
	esac
	shift
done

if [[ -n "$requested_shot" && "$requested_shot" != "__gif__" ]]; then
	found=0
	for recipe in "${RECIPES[@]}" "${GIF_RECIPES[@]}"; do
		[[ "$recipe" == "$requested_shot" ]] && found=1
	done
	if [[ "$found" -ne 1 ]]; then
		echo "receita desconhecida: '$requested_shot'; veja --list" >&2
		exit 2
	fi
	RECIPES=("$requested_shot")
fi

command -v godot >/dev/null 2>&1 || { echo "godot nao encontrado no PATH" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# AVI (Movie Maker) -> GIF: corta o fim do video, que e o trecho com o ataque.
encode_variant_gif() {
	local recipe="$1"
	local avi="$OUT_DIR/$recipe.avi"
	local gif="$GIF_DIR/$recipe.gif"
	if [[ ! -f "$avi" ]]; then
		echo "   FALHOU: sem AVI do --write-movie" >&2
		return 1
	fi
	mkdir -p "$GIF_DIR"
	if ! ffmpeg -y -sseof -4.2 -i "$avi" \
		-vf "fps=14,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
		-loop 0 "$gif" > /dev/null 2>&1; then
		echo "   FALHOU: ffmpeg nao gerou $gif" >&2
		return 1
	fi
	echo "   gif: docs/imagens/zumbis/$recipe.gif ($(du -h "$gif" | cut -f1))"
}


# Flags extras por receita (o que nao da para decidir dentro do jogo).
extra_flags_for() {
	case "$1" in
		horda-onda-alta) echo "--test-wave=8" ;;
		tela-dividida) echo "--local-players=4" ;;
		pvp-*) echo "--join=127.0.0.1 --server-port=27015" ;;
		*) echo "" ;;
	esac
}

failures=()
for recipe in "${RECIPES[@]}"; do
	# shellcheck disable=SC2046 # flags extras sao simples e sem espacos
	extra="$(extra_flags_for "$recipe")"
	echo ">> capturando '$recipe' ${extra:+(+ $extra)}"
	rm -f "$OUT_DIR/$recipe.png"
	engine_flags=""
	if [[ "$recipe" == zumbi-* ]]; then
		# Movie Maker: grava o processo inteiro em AVI; o ffmpeg corta o fim.
		engine_flags="--write-movie $OUT_DIR/$recipe.avi --fixed-fps 15"
	fi
	# shellcheck disable=SC2086 # divisao intencional das flags extras
	timeout "$CAPTURE_TIMEOUT" godot --path "$PROJECT_DIR" --windowed $engine_flags -- \
		--capture=dist/capturas --shot="$recipe" --perf-probe=off $extra \
		> "$OUT_DIR/$recipe.log" 2>&1 || true
	if [[ ! -f "$OUT_DIR/$recipe.png" ]]; then
		echo "   FALHOU: sem PNG; ultimas linhas do log:" >&2
		grep -E "shot_capture|SCRIPT ERROR|Parse Error" "$OUT_DIR/$recipe.log" | tail -5 >&2 || true
		failures+=("$recipe")
		continue
	fi
	size="$(du -h "$OUT_DIR/$recipe.png" | cut -f1)"
	echo "   ok: dist/capturas/$recipe.png ($size)"
	if [[ "$recipe" == zumbi-* ]]; then
		if encode_variant_gif "$recipe"; then
			rm -f "$OUT_DIR/$recipe.avi"
		else
			rm -f "$OUT_DIR/$recipe.avi"
			failures+=("$recipe")
		fi
	fi
done

if [[ "${#failures[@]}" -gt 0 ]]; then
	echo "receitas com falha: ${failures[*]}" >&2
	exit 1
fi

if [[ "$optimize" -eq 1 ]]; then
	command -v magick >/dev/null 2>&1 || { echo "magick (ImageMagick) nao encontrado; use --no-optimize" >&2; exit 1; }
	mkdir -p "$IMG_DIR"
	echo ">> otimizando para docs/imagens (${OPTIMIZE_WIDTH}px, q${OPTIMIZE_QUALITY})"
	for recipe in "${RECIPES[@]}"; do
		[[ "$recipe" == zumbi-* ]] && continue
		magick "$OUT_DIR/$recipe.png" \
			-resize "${OPTIMIZE_WIDTH}x" -strip -interlace Plane -quality "$OPTIMIZE_QUALITY" \
			"$IMG_DIR/$recipe.jpg"
		echo "   docs/imagens/$recipe.jpg ($(du -h "$IMG_DIR/$recipe.jpg" | cut -f1))"
	done
fi

echo "pronto. Brutos: $OUT_DIR | Finais: $IMG_DIR"
