#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Checagem padrao de sessao: sobe servidor + cliente e valida o que importa em
# jogo, em duas fases:
#   1) movimento: servidor com --smoke-test-zombie e cliente bot (--bot), que so
#      passa se conectou, ANDOU, gastou stamina, viu bala e matou zumbi;
#   2) esquadrao SWAT: servidor com --smoke-test-swat e cliente com
#      --smoke-test-swat, que so passa se os 4 soldados existem NO CLIENTE e se
#      movem (foi o bug de hoje: com o id de peer negativo lido como u32 o
#      estado era descartado e o soldado ficava parado na origem, invisivel).
# Tambem exige a linha de build nos dois lados, o handshake de versao aceito e
# zero erro de RPC/checksum.
#
# Uso:
#   scripts/test_session.sh [porta]
#   SESSION_BIN=dist/box-godot-linux.x86_64 scripts/test_session.sh 27015
set -uo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${1:-7050}"
godot_bin="${SESSION_BIN:-godot}"
work_dir="$(mktemp -d)"
failures=0

run_engine() {
	# $1 = log, resto = argumentos do jogo (depois de --)
	local log="$1"
	shift
	if [[ "$godot_bin" == */* ]]; then
		timeout 35s stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- "$@" >"$log" 2>&1
	else
		timeout 35s stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- "$@" >"$log" 2>&1
	fi
}

start_server() {
	# $1 = log, resto = argumentos do servidor
	local log="$1"
	shift
	if [[ "$godot_bin" == */* ]]; then
		stdbuf -oL -eL "$project_dir/$godot_bin" --headless -- --server "--server-port=$port" "$@" >"$log" 2>&1 &
	else
		stdbuf -oL -eL "$godot_bin" --headless --path "$project_dir" -- --server "--server-port=$port" "$@" >"$log" 2>&1 &
	fi
	echo $!
}

check() {
	# $1 = descricao, $2 = arquivo, $3 = padrao (grep -E)
	if grep -qE "$3" "$2"; then
		printf 'PASS: %s\n' "$1"
	else
		printf 'FALHA: %s (procurei /%s/ em %s)\n' "$1" "$3" "$2"
		failures=$((failures + 1))
	fi
}

check_absent() {
	local log="$1"
	local pattern="$2"
	if grep -qE "$pattern" "$log"; then
		printf 'FALHA: erro no log %s:\n' "$log"
		grep -E "$pattern" "$log" | head -5
		failures=$((failures + 1))
	else
		printf 'PASS: sem erro em %s\n' "$(basename "$log")"
	fi
}

printf '%s\n' "Fase 1/3: movimento do jogador (servidor + bot)..."
server_pid="$(start_server "$work_dir/move_server.log" --smoke-test-zombie)"
sleep 3
run_engine "$work_dir/move_bot.log" "--bot=127.0.0.1" "--server-port=$port"
kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
check "servidor imprime o build" "$work_dir/move_server.log" '"event":"build".*"role":"server"'
check "cliente imprime o build" "$work_dir/move_bot.log" '"event":"build".*"role":"client"'
check "servidor aceita o handshake de build" "$work_dir/move_server.log" 'reportou build .*\(ok\)'
check "jogador conectou, andou e matou um zumbi" "$work_dir/move_bot.log" 'BOT_TEST_PASS'

printf '%s\n' "Fase 2/3: esquadrao SWAT visivel e se movendo no cliente..."
server_pid="$(start_server "$work_dir/swat_server.log" --smoke-test-swat)"
sleep 3
run_engine "$work_dir/swat_client.log" "--join=127.0.0.1" "--server-port=$port" --smoke-test-swat
kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
check "servidor criou o esquadrao" "$work_dir/swat_server.log" '"event":"swat_smoke_called"'
check "cliente ve os 4 soldados" "$work_dir/swat_client.log" '"alive":4,"at_origin":0,"event":"swat_seen_done"'
check "soldados se movem no cliente (max_travel > 0.5)" "$work_dir/swat_client.log" '"max_travel":([1-9][0-9]*|0\.[5-9])'

printf '%s\n' "Fase 3/3: cliente de build diferente e recusado sem sujar o roster..."
server_pid="$(start_server "$work_dir/reject_server.log" --smoke-test-zombie)"
sleep 3
run_engine "$work_dir/reject_client.log" "--join=127.0.0.1" "--server-port=$port" --fake-build=0000-00-00.0
kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
check "servidor recusa o build diferente" "$work_dir/reject_server.log" 'recusado: Build do cliente diferente'
# O bug: _report_build derrubava o peer, mas o _request_slots que o cliente ja
# tinha mandado na mesma leva chegava depois e entrava no roster assim mesmo.
check "peer recusado NAO entra no roster" "$work_dir/reject_server.log" 'pediu vaga sem passar pelo handshake'
check_absent "$work_dir/reject_server.log" 'entrou com [0-9]+ jogador'
check_absent "$work_dir/reject_server.log" 'Unable to send packet'

check_absent "$work_dir/move_server.log" 'checksum|SCRIPT ERROR|RPC -'
check_absent "$work_dir/move_bot.log" 'checksum|SCRIPT ERROR|RPC -'
check_absent "$work_dir/swat_server.log" 'checksum|SCRIPT ERROR|RPC -'
check_absent "$work_dir/swat_client.log" 'checksum|SCRIPT ERROR|RPC -'

if ((failures > 0)); then
	printf '\n%s\n' "SESSION_TEST_FAIL: $failures verificacao(oes) falharam; logs em $work_dir"
	exit 1
fi
printf '\n%s\n' "SESSION_TEST_PASS: build, handshake, movimento, SWAT visivel/se movendo e recusa limpa de build velho."
printf '%s\n' "Logs em $work_dir"
