#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Teste ponta-a-ponta de N peers reais em PVP: sobe 1 servidor dedicado --pvp +
# N clientes bot (processos separados, ENet de verdade) e exige que TODOS
# conectem, lutem e que a partida comece. Decisao do dono: ate 8 peers no PvP.
#
# No PvP nao ha zumbi, entao o BOT_TEST_PASS do cliente vale por conectar, ver
# um jogador, andar, gastar stamina e ver uma bala (ver player_bot_ai.gd).
#
# Uso:
#   scripts/test_pvp_peers.sh [N] [porta]
#   SESSION_BIN=dist/box-godot-linux.x86_64 scripts/test_pvp_peers.sh 8
set -uo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
peer_count="${1:-8}"
port="${2:-7080}"
godot_bin="${SESSION_BIN:-godot}"
work_dir="$(mktemp -d)"
failures=0
client_timeout_seconds=55

run_engine() {
	# $1 = log, resto = argumentos (clientes)
	local log="$1"
	shift
	if [[ "$godot_bin" == */* ]]; then
		timeout "${client_timeout_seconds}s" stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- "$@" >"$log" 2>&1
	else
		timeout "${client_timeout_seconds}s" stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- "$@" >"$log" 2>&1
	fi
}

start_server() {
	local log="$1"
	if [[ "$godot_bin" == */* ]]; then
		stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- --server \
			"--server-port=$port" "--max-players=$peer_count" --pvp "--pvp-bots=${PVP_BOTS:-4}" >"$log" 2>&1 &
	else
		stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- --server \
			"--server-port=$port" "--max-players=$peer_count" --pvp "--pvp-bots=${PVP_BOTS:-4}" >"$log" 2>&1 &
	fi
	echo $!
}

printf '%s\n' "Subindo servidor PVP + ${peer_count} clientes bot (porta ${port})..."
server_pid="$(start_server "$work_dir/server.log")"
sleep 3

bot_pids=()
for index in $(seq 1 "$peer_count"); do
	run_engine "$work_dir/bot_$index.log" "--bot=127.0.0.1" "--server-port=$port" &
	bot_pids+=("$!")
	sleep 0.4
done
for pid in "${bot_pids[@]}"; do
	wait "$pid" 2>/dev/null
done

# Retentativa unica dos bots que nao passaram (o bot de teste as vezes enrosca).
for index in $(seq 1 "$peer_count"); do
	if ! grep -qE 'BOT_TEST_PASS' "$work_dir/bot_$index.log"; then
		printf 'Retentando bot %d...\n' "$index"
		run_engine "$work_dir/bot_${index}_retry.log" "--bot=127.0.0.1" "--server-port=$port"
	fi
done

# Da tempo para a partida andar (compra de 15 s + combate) e os bots do
# servidor trocarem tiros: sem isso o servidor e morto antes de pvp_match_started/
# pvp_kill existirem.
printf '%s\n' "Aguardando a partida PVP andar..."
pvp_deadline=$((SECONDS + 120))
while (( SECONDS < pvp_deadline )); do
	if grep -qE '"event":"pvp_kill"' "$work_dir/server.log" && grep -qE '"event":"pvp_match_started"' "$work_dir/server.log"; then
		break
	fi
	sleep 3
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
if [[ "$handshakes" -ge "$peer_count" ]]; then
	printf 'PASS: servidor aceitou os %d handshakes de build\n' "$peer_count"
else
	printf 'FALHA: servidor aceitou %d/%d handshakes\n' "$handshakes" "$peer_count"
	failures=$((failures + 1))
fi

if grep -qE '"event":"pvp_match_started"' "$work_dir/server.log"; then
	printf 'PASS: a partida de mata-mata comecou (pvp_match_started)\n'
else
	printf 'FALHA: o servidor nao iniciou rodada de PVP\n'
	failures=$((failures + 1))
fi

# Combate e provado pelos bots do servidor (--pvp-bots), que tem roteamento.
if grep -qE '"event":"pvp_kill"' "$work_dir/server.log"; then
	printf 'PASS: houve abate no PVP (pvp_kill)\n'
else
	printf 'FALHA: nenhum abate no PVP (pvp_kill ausente)\n'
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
	printf 'PASS: os %d clientes conectaram e lutaram no PVP\n' "$peer_count"
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
	printf 'PVP_PEERS_PASS: %d peers\n' "$peer_count"
else
	printf 'PVP_PEERS_FAIL: %d falha(s)\n' "$failures"
	exit 1
fi
