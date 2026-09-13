#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${GAME_SERVER_PORT:-27015}"

cleanup() {
	docker compose --project-directory "$project_dir" down --remove-orphans
}
trap cleanup EXIT

GAME_SERVER_PORT="$port" GAME_SERVER_TEST_MODE=--smoke-test-zombie docker compose --project-directory "$project_dir" up --build --detach
sleep 3
set +e
bot_output="$(timeout 25s godot --headless --path "$project_dir" -- --bot=127.0.0.1 "--server-port=$port" 2>&1)"
bot_status=$?
set -e
printf '%s\n' "$bot_output"
server_logs="$(GAME_SERVER_PORT="$port" docker compose --project-directory "$project_dir" logs game-server)"
printf '%s\n' "$server_logs"
if (( bot_status != 0 )); then
	printf '%s\n' "Falha: o bot Godot encerrou com codigo $bot_status." >&2
	exit "$bot_status"
fi
if [[ "$server_logs" == *"SCRIPT ERROR"* || "$server_logs" == *"ERROR:"* || "$server_logs" == *"above the MTU"* || "$bot_output" == *"SCRIPT ERROR"* || "$bot_output" == *"ERROR:"* || "$bot_output" == *"above the MTU"* ]]; then
	printf '%s\n' "Falha: o servidor Docker ou cliente Godot registrou erros durante o smoke test." >&2
	exit 1
fi
