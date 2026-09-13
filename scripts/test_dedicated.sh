#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${1:-7010}"
server_pid=""
server_log="$(mktemp)"

cleanup() {
	if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
		kill "$server_pid"
		wait "$server_pid" 2>/dev/null || true
	fi
	rm -f "$server_log"
}
trap cleanup EXIT

# Executa suite de testes unitarios de combate, fogo amigo e variantes anatomicas
godot --headless --path "$project_dir" -- --unit-test

godot --headless --path "$project_dir" -- --server "--server-port=$port" >"$server_log" 2>&1 &
server_pid=$!
sleep 1

set +e
bot_output="$(timeout 25s godot --headless --path "$project_dir" -- --bot=127.0.0.1 "--server-port=$port" 2>&1)"
bot_status=$?
set -e
printf '%s\n' "$bot_output"
kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=""
server_output="$(<"$server_log")"
printf '%s\n' "$server_output"
if (( bot_status != 0 )); then
	printf '%s\n' "Falha: o bot Godot encerrou com codigo $bot_status." >&2
	exit "$bot_status"
fi
if [[ "$server_output" == *"SCRIPT ERROR"* || "$server_output" == *"ERROR:"* || "$server_output" == *"above the MTU"* || "$bot_output" == *"SCRIPT ERROR"* || "$bot_output" == *"ERROR:"* || "$bot_output" == *"above the MTU"* ]]; then
	printf '%s\n' "Falha: o servidor ou cliente Godot registrou erros durante o smoke test." >&2
	exit 1
fi
