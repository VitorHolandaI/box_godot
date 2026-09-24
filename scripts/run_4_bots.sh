#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Abre 4 janelas de bots jogando sozinhos. Sem alvo, sobe um servidor dedicado
# local; com alvo (ex.: o VPS), os bots entram nele e nenhum servidor local sobe.
# Uso:
#   scripts/run_4_bots.sh [porta] [ip_do_servidor]
#   scripts/run_4_bots.sh 27015 203.0.113.10
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${1:-7070}"
target_ip="${2:-127.0.0.1}"
server_pid=""
bot_pids=()

cleanup() {
	printf '\n%s\n' "Encerrando servidor e janelas dos bots..."
	for pid in "${bot_pids[@]}"; do
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
		kill "$server_pid" 2>/dev/null || true
		wait "$server_pid" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

# Detecta resolucao de tela se ferramentas graficas estiverem presentes
screen_w=1920
screen_h=1080
if command -v xrandr >/dev/null 2>&1; then
	detected_res="$(xrandr 2>/dev/null | grep '\*' | head -n1 | awk '{print $1}' || true)"
	if [[ "$detected_res" =~ ^([0-9]+)x([0-9]+)$ ]]; then
		screen_w="${BASH_REMATCH[1]}"
		screen_h="${BASH_REMATCH[2]}"
	fi
elif command -v xdpyinfo >/dev/null 2>&1; then
	detected_res="$(xdpyinfo 2>/dev/null | grep dimensions | awk '{print $2}' || true)"
	if [[ "$detected_res" =~ ^([0-9]+)x([0-9]+)$ ]]; then
		screen_w="${BASH_REMATCH[1]}"
		screen_h="${BASH_REMATCH[2]}"
	fi
fi

if (( screen_w >= 1920 && screen_h >= 1000 )); then
	win_w="${BOT_WIDTH:-920}"
	win_h="${BOT_HEIGHT:-520}"
	pos_x1=30
	pos_x2=970
	pos_y1=40
	pos_y2=580
else
	win_w="${BOT_WIDTH:-640}"
	win_h="${BOT_HEIGHT:-360}"
	pos_x1=20
	pos_x2=680
	pos_y1=30
	pos_y2=410
fi

positions=(
	"$pos_x1,$pos_y1"
	"$pos_x2,$pos_y1"
	"$pos_x1,$pos_y2"
	"$pos_x2,$pos_y2"
)

bot_names=(
	"Bot Alfa"
	"Bot Bravo"
	"Bot Charlie"
	"Bot Delta"
)

if [[ "$target_ip" == "127.0.0.1" ]]; then
	printf '%s\n' "Iniciando servidor dedicado local em UDP $port..."
	godot --headless --path "$project_dir" -- --server "--server-port=$port" >/dev/null 2>&1 &
	server_pid=$!
	sleep 1.2
else
	printf '%s\n' "Servidor remoto: $target_ip:$port (nenhum servidor local sobe)."
fi

bot_fps="${BOT_FPS:-60}"
bot_quality="${BOT_QUALITY:-medium}"

printf '\n%s\n' "Abrindo 4 janelas de jogadores bots (${win_w}x${win_h}, FPS max: $bot_fps, qualidade: $bot_quality):"
for i in {0..3}; do
	pos="${positions[$i]}"
	name="${bot_names[$i]}"
	printf '  - Janela %d: %-12s na posicao %s\n' "$((i + 1))" "$name" "$pos"
	godot --windowed --resolution "${win_w}x${win_h}" --position "$pos" --path "$project_dir" \
		-- "--bot-player=$target_ip" "--server-port=$port" "--bot-name=$name" \
		"--max-fps=$bot_fps" "--quality=$bot_quality" &
	bot_pids+=($!)
	sleep 0.35
done

printf '\n%s\n' "============================================================"
printf '%s\n' " 4 Jogadores Bots jogando sozinhos em 4 janelas simultaneas!"
printf '%s\n' " Servidor: $target_ip:$port"
printf '%s\n' " Pressione Ctrl+C para fechar todos os bots e o servidor."
printf '%s\n\n' "============================================================"

wait "${bot_pids[@]}" 2>/dev/null || true
