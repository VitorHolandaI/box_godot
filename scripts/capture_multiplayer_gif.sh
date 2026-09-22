#!/usr/bin/env bash
# Sobe uma partida TDM local com bots e grava o cliente que recebe os snapshots.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/dist/capturas"
PORT="${CAPTURE_SERVER_PORT:-27115}"
SERVER_LOG="$OUT_DIR/multiplayer-pvp-server.log"

mkdir -p "$OUT_DIR"
godot --headless --path "$PROJECT_DIR" -- \
	--server --pvp --pvp-bots=4 --server-port="$PORT" \
	> "$SERVER_LOG" 2>&1 &
server_pid=$!

cleanup() {
	if kill -0 "$server_pid" 2>/dev/null; then
		kill "$server_pid"
		wait "$server_pid" || true
	fi
}
trap cleanup EXIT

sleep 2
CAPTURE_SERVER_PORT="$PORT" bash "$PROJECT_DIR/scripts/capture_shots.sh" \
	--shot=multiplayer-pvp --no-optimize
