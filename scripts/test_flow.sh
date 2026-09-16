#!/usr/bin/env bash
set -euo pipefail

# Teste de fluxos end-to-end: servidor dedicado com auditoria de fluxos
# (--flow-audit) + bot client jogando por N segundos; o servidor imprime
# FLOW_AUDIT {...} e encerra com 0 (nucleo ok) ou 1 (algum fluxo nuclear falhou).
# Uso: bash scripts/test_flow.sh [porta] [segundos]

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${1:-7020}"
duration="${2:-75}"
server_log="$(mktemp)"

cleanup() {
	rm -f "$server_log"
}
trap cleanup EXIT

godot --headless --path "$project_dir" -- --server "--server-port=$port" "--flow-audit=$duration" >"$server_log" 2>&1 &
server_pid=$!

sleep 1
# Bot joga ate o fim da auditoria; o server encerra sozinho no tempo limite.
timeout "$((duration + 10))s" godot --headless --path "$project_dir" -- --bot=127.0.0.1 "--server-port=$port" >/dev/null 2>&1 || true

wait "$server_pid" 2>/dev/null || true
server_output="$(<"$server_log")"
printf '%s\n' "$server_output" | grep -E "FLOW_AUDIT|stutter" || true

if printf '%s\n' "$server_output" | grep -q '"core_failed":\[\]'; then
	printf '%s\n' "FLOW_TEST_PASS: todos os fluxos nucleares validados."
else
	printf '%s\n' "FLOW_TEST_FAIL: veja o relatorio FLOW_AUDIT acima." >&2
	exit 1
fi
