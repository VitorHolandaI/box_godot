#!/usr/bin/env bash
# Menu do servidor local (docker compose): escolhe NA HORA qual modo subir, se
# precisa rebuildar, e ainda parar/logs/status. O compose tem um servico so
# (`game-server`); o modo vai por variavel de ambiente, entao trocar de modo
# recria o container.
#
# Uso:
#   scripts/server_menu.sh                    # menu interativo
#   scripts/server_menu.sh pvp up             # mata-mata: rebuild + sobe
#   scripts/server_menu.sh survival start     # sobrevivencia: sobe sem rebuild
#   scripts/server_menu.sh pvp restart        # recria o container
#   scripts/server_menu.sh stop               # derruba
#   scripts/server_menu.sh logs               # segue o log
#   scripts/server_menu.sh status             # o que esta no ar
#   PVP_BOTS=4 scripts/server_menu.sh pvp up  # mata-mata com 4 bots (teste)
#   CAR_BOT=0 scripts/server_menu.sh survival up  # sem bot dirigindo o carro
#   PORT=32000 scripts/server_menu.sh pvp up  # outra porta (2o servidor)
#   DRY_RUN=1 scripts/server_menu.sh pvp up   # so mostra o comando
#   scripts/server_menu.sh self-test          # testa o script (sem docker)
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

godot_server_bin="dist/box-godot-linux.x86_64"
## PVP sem bots por padrao (jogo de verdade). PVP_BOTS=N pede bots de teste.
default_pvp_bots="${PVP_BOTS:-0}"
## Bot dirigindo o carro no servidor local (teste da rede do veiculo). CAR_BOT=0
## desliga; CAR_BOT=N poe bot em ate N carros.
default_car_bot="${CAR_BOT:-1}"

usage() {
	cat <<'TXT'
Uso: scripts/server_menu.sh [modo] [acao]

  modo: survival | pvp            (o que subir)
  acao: up (rebuild+sobe) | start (sobe) | restart | stop | logs | status
        self-test (checa o script sem docker)

Sem argumentos abre o menu interativo. Variaveis: PVP_BOTS, CAR_BOT, PORT, DRY_RUN.
TXT
}

die() {
	# Mensagem de erro sempre com o valor ofensor e o esperado.
	echo "erro: $1" >&2
	exit 1
}

require_docker() {
	command -v docker >/dev/null 2>&1 || die "docker nao encontrado no PATH (esperado o binario 'docker' com o plugin 'compose')"
	docker compose version >/dev/null 2>&1 || die "plugin 'docker compose' indisponivel (esperado 'docker compose version' funcionando)"
}

require_mode() {
	local mode="$1"
	case "$mode" in
		survival | pvp) ;;
		*) die "modo desconhecido: '$mode' (esperado 'survival' ou 'pvp')" ;;
	esac
}

require_action() {
	local action="$1"
	case "$action" in
		up | start | restart | stop | logs | status | self-test) ;;
		*) die "acao desconhecida: '$action' (esperado up|start|restart|stop|logs|status|self-test)" ;;
	esac
}

# Exporta as variaveis que o compose le para o modo pedido. A sobrevivencia
# zera os bots de PVP de proposito: assim o que esta no ar fica explicito no
# `docker compose config`, sem depender do default do compose.
export_mode_env() {
	local mode="$1"
	case "$mode" in
		survival)
			export GAME_SERVER_GAME_MODE="--survival"
			export GAME_SERVER_PVP_BOTS="--pvp-bots=0"
			;;
		pvp)
			[[ "$default_pvp_bots" =~ ^[0-9]+$ ]] || die "PVP_BOTS invalido: '$default_pvp_bots' (esperado inteiro >= 0)"
			export GAME_SERVER_GAME_MODE="--pvp"
			export GAME_SERVER_PVP_BOTS="--pvp-bots=$default_pvp_bots"
			;;
	esac
	[[ "$default_car_bot" =~ ^[0-9]+$ ]] || die "CAR_BOT invalido: '$default_car_bot' (esperado inteiro >= 0)"
	export GAME_SERVER_CAR_BOT="--car-bot=$default_car_bot"
	if [[ -n "${PORT:-}" ]]; then
		[[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT invalido: '$PORT' (esperado inteiro)"
		export GAME_SERVER_PORT="$PORT"
	fi
	export GAME_SERVER_NAME="${SERVER_NAME:-}"
}

# Prefixo com as variaveis de modo, para o dry-run mostrar exatamente o comando
# que subiria (e para o log deixar claro o que foi escolhido).
mode_env_prefix() {
	local prefix=""
	local name
	for name in GAME_SERVER_GAME_MODE GAME_SERVER_PVP_BOTS GAME_SERVER_CAR_BOT GAME_SERVER_PORT GAME_SERVER_NAME; do
		if [[ -n "${!name:-}" ]]; then
			prefix+="$name=${!name} "
		fi
	done
	echo "$prefix"
}

compose() {
	if [[ "${DRY_RUN:-0}" == "1" ]]; then
		echo ">> [dry-run] $(mode_env_prefix)docker compose $*"
		return 0
	fi
	echo ">> docker compose $*"
	docker compose "$@"
}

port_in_use() {
	echo "${GAME_SERVER_PORT:-27015}"
}

action_up() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	compose up -d --build game-server
	announce "$mode"
}

action_start() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	compose up -d game-server
	announce "$mode"
}

action_restart() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	compose up -d --force-recreate game-server
	announce "$mode"
}

action_stop() {
	require_docker
	compose down
	echo "servidor parado"
}

action_logs() {
	require_docker
	compose logs -f --tail=80 game-server
}

action_status() {
	require_docker
	compose ps
}

run_without_mode() {
	local action="$1"
	case "$action" in
		stop) action_stop ;;
		logs) action_logs ;;
		status) action_status ;;
	esac
}

announce() {
	local mode="$1"
	local port
	port="$(port_in_use)"
	local label="sobrevivencia (zumbis, hordas)"
	if [[ "$mode" == "pvp" ]]; then
		if [[ "$default_pvp_bots" == "0" ]]; then
			label="mata-mata PVP (sem bots, best-of-3)"
		else
			label="mata-mata PVP (${default_pvp_bots} bots, best-of-3)"
		fi
	fi
	echo
	echo "no ar: $label | porta $port"
	echo "conectar: $godot_server_bin -- --join=127.0.0.1 --server-port=$port"
	echo "log:      scripts/server_menu.sh logs"
}

# self-test: valida a escolha de modo/acao, o comando gerado e a recusa de
# entrada invalida. Nao precisa de docker nem de rede.
self_test() {
	local failures=0
	local output

	check_contains() {
		local haystack="$1"
		local needle="$2"
		local what="$3"
		if [[ "$haystack" != *"$needle"* ]]; then
			echo "FALHA: $what (esperava encontrar '$needle' em: $haystack)"
			failures=$((failures + 1))
			return
		fi
		echo "PASS: $what"
	}

	output="$(DRY_RUN=1 "$0" pvp up)"
	check_contains "$output" "--pvp-bots=0" "pvp up sobe SEM bots por padrao"
	check_contains "$output" "--build" "pvp up rebuilda a imagem"
	check_contains "$output" "server-port=27015" "cliente na porta padrao"

	output="$(DRY_RUN=1 PVP_BOTS=4 "$0" pvp start)"
	check_contains "$output" "--pvp-bots=4" "PVP_BOTS=4 pede bots de teste"
	if [[ "$output" == *"--build"* ]]; then
		echo "FALHA: pvp start nao pode rebuildar"
		failures=$((failures + 1))
	else
		echo "PASS: pvp start nao rebuilda"
	fi

	output="$(DRY_RUN=1 "$0" survival up)"
	check_contains "$output" "--survival" "survival up usa o modo sobrevivencia"
	check_contains "$output" "--pvp-bots=0" "survival zera os bots de PVP"

	output="$(DRY_RUN=1 PORT=32000 "$0" survival start)"
	check_contains "$output" "server-port=32000" "PORT alternativo respeitado"

	output="$(DRY_RUN=1 "$0" status)"
	check_contains "$output" "docker compose ps" "status funciona sem escolher modo"

	if "$0" zumbi up >/dev/null 2>&1; then
		echo "FALHA: modo invalido deveria sair com erro"
		failures=$((failures + 1))
	else
		echo "PASS: modo invalido recusado"
	fi
	if "$0" pvp voar >/dev/null 2>&1; then
		echo "FALHA: acao invalida deveria sair com erro"
		failures=$((failures + 1))
	else
		echo "PASS: acao invalida recusada"
	fi

	if [[ "$failures" -gt 0 ]]; then
		echo "SELF_TEST_FAIL: $failures falha(s)"
		return 1
	fi
	echo "SELF_TEST_PASS: menu do servidor ok"
}

interactive_menu() {
	while true; do
		echo
		echo "=== servidor local (box_godot) ==="
		echo "1) sobrevivencia  - rebuild + subir"
		if [[ "$default_pvp_bots" == "0" ]]; then
			echo "2) mata-mata PVP  - rebuild + subir (sem bots)"
		else
			echo "2) mata-mata PVP  - rebuild + subir (${default_pvp_bots} bots)"
		fi
		echo "3) sobrevivencia  - subir sem rebuild"
		echo "4) mata-mata PVP  - subir sem rebuild"
		echo "5) parar servidor"
		echo "6) ver log (segue, Ctrl+C sai)"
		echo "7) status"
		echo "8) sair"
		local choice=""
		if ! read -rp "escolha: " choice; then
			echo
			return 0
		fi
		case "$choice" in
			1) action_up survival ;;
			2) action_up pvp ;;
			3) action_start survival ;;
			4) action_start pvp ;;
			5) action_stop ;;
			6) action_logs ;;
			7) action_status ;;
			8) return 0 ;;
			"") ;;
			*) echo "opcao invalida: '$choice' (esperado 1 a 8)" ;;
		esac
	done
}

main() {
	local mode="${1:-}"
	local action="${2:-}"
	if [[ -z "$mode" ]]; then
		interactive_menu
		return 0
	fi
	if [[ "$mode" == "-h" || "$mode" == "--help" ]]; then
		usage
		return 0
	fi
	if [[ "$mode" == "self-test" ]]; then
		self_test
		return 0
	fi
	# Acoes que nao dependem de modo: parar/ver log/status valem sem escolher
	# sobrevivencia ou PVP (o compose tem um servico so).
	case "$mode" in
		stop | logs | status)
			run_without_mode "$mode"
			return 0
			;;
	esac
	require_mode "$mode"
	action="${action:-up}"
	require_action "$action"
	case "$action" in
		up) action_up "$mode" ;;
		start) action_start "$mode" ;;
		restart) action_restart "$mode" ;;
		stop) action_stop ;;
		logs) action_logs ;;
		status) action_status ;;
		self-test) self_test ;;
	esac
}

main "$@"
