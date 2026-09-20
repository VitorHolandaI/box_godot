#!/usr/bin/env bash
# Teste ponta-a-ponta de multiplayer com N peers reais: sobe 1 servidor
# dedicado + N clientes bot em processos separados (ENet de verdade, sem
# simular dentro de um processo so) e exige que TODOS conectem e joguem.
# Decisao do dono (2026-09-20): ate 8 peers no PvE e no PvP.
#
# Uso:
#   scripts/test_multiplayer_peers.sh [N] [porta]
#   SESSION_BIN=dist/box-godot-linux.x86_64 scripts/test_multiplayer_peers.sh 8
set -uo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
peer_count="${1:-8}"
port="${2:-7060}"
godot_bin="${SESSION_BIN:-godot}"
work_dir="$(mktemp -d)"
failures=0
client_timeout_seconds=55
# Zumbis de sobra para os N bots terem alvo e imprimirem BOT_TEST_PASS.
prespawn_zombies=24

start_server() {
	# $1 = log, resto = argumentos extras do servidor
	local log="$1"
	shift
	if [[ "$godot_bin" == */* ]]; then
		stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- --server \
			"--server-port=$port" "--max-players=$peer_count" "$@" >"$log" 2>&1 &
	else
		stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- --server \
			"--server-port=$port" "--max-players=$peer_count" "$@" >"$log" 2>&1 &
	fi
	echo $!
}

run_bot() {
	local log="$1"
	if [[ "$godot_bin" == */* ]]; then
		timeout "${client_timeout_seconds}s" stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- \
			"--bot=127.0.0.1" "--server-port=$port" >"$log" 2>&1
	else
		timeout "${client_timeout_seconds}s" stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- \
			"--bot=127.0.0.1" "--server-port=$port" >"$log" 2>&1
	fi
}

printf '%s\n' "Subindo servidor + ${peer_count} clientes bot (porta ${port})..."
server_pid="$(start_server "$work_dir/server.log" --smoke-test-zombie "--prespawn-zombies=$prespawn_zombies")"
sleep 3

bot_pids=()
# Escalona as entradas (~0.4 s): 8 bots saindo do abrigo no mesmo instante
# congestionavam a porta e um deles ficava preso sem andar.
for index in $(seq 1 "$peer_count"); do
	run_bot "$work_dir/bot_$index.log" &
	bot_pids+=("$!")
	sleep 0.4
done
for pid in "${bot_pids[@]}"; do
	wait "$pid" 2>/dev/null
done

# Retentativa unica dos bots que nao passaram. O bot de teste anda em linha
# reta ate o alvo e pode enroscar numa parede do abrigo (limitacao do bot, nao
# do jogo); a conexao e o handshake de TODOS os peers ja foram provados acima.
for index in $(seq 1 "$peer_count"); do
	if ! grep -qE 'BOT_TEST_PASS' "$work_dir/bot_$index.log"; then
		printf 'Retentando bot %d...\n' "$index"
		run_bot "$work_dir/bot_${index}_retry.log"
	fi
done

kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null

if grep -qE '"event":"build".*"role":"server"' "$work_dir/server.log"; then
	printf 'PASS: servidor imprimiu o build\n'
else
	printf 'FALHA: servidor sem a linha de build\n'
	failures=$((failures + 1))
fi

handshakes="$(grep -cE 'reportou build .*\(ok\)' "$work_dir/server.log" || true)"
if [[ "$handshakes" -eq "$peer_count" ]]; then
	printf 'PASS: servidor aceitou os %d handshakes de build\n' "$peer_count"
else
	printf 'FALHA: servidor aceitou %d/%d handshakes\n' "$handshakes" "$peer_count"
	failures=$((failures + 1))
fi

pass_count=0
	for index in $(seq 1 "$peer_count"); do
	if grep -qE 'BOT_TEST_PASS' "$work_dir/bot_$index.log" "$work_dir/bot_${index}_retry.log" 2>/dev/null; then
		pass_count=$((pass_count + 1))
	else
		printf 'FALHA: bot %d nao passou; ultimas linhas:\n' "$index"
		tail -n 3 "$work_dir/bot_$index.log"
	fi
done
if [[ "$pass_count" -eq "$peer_count" ]]; then
	printf 'PASS: os %d clientes conectaram, andaram e jogaram\n' "$peer_count"
else
	printf 'FALHA: %d/%d clientes jogaram\n' "$pass_count" "$peer_count"
	failures=$((failures + 1))
fi

for log in "$work_dir"/*.log; do
	if grep -qE 'SCRIPT ERROR|Invalid call|rpc node checksum failed' "$log"; then
		printf 'FALHA: erro no log %s:\n' "$log"
		grep -E 'SCRIPT ERROR|Invalid call|rpc node checksum failed' "$log" | head -n 3
		failures=$((failures + 1))
	fi
done

if [[ "$failures" -eq 0 ]]; then
	printf 'MULTIPLAYER_PEERS_PASS: %d peers\n' "$peer_count"
else
	printf 'MULTIPLAYER_PEERS_FAIL: %d falha(s)\n' "$failures"
	exit 1
fi
