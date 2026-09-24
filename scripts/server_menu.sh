#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Menu do servidor local (docker compose): escolhe NA HORA qual modo subir, se
# precisa rebuildar, e ainda parar/logs/status.
#
# Cada modo e um SERVICO proprio no compose (survival | tdm | classic), com
# porta e container proprios, seleciondo por profile. Antes havia um servico so
# e o modo ia por variavel de ambiente: trocar de modo recriava o mesmo
# container e o modo no ar so aparecia lendo o `command` dele.
#
# Uso:
#   scripts/server_menu.sh                    # menu interativo
#   scripts/server_menu.sh tdm up             # mata-mata: rebuild + sobe
#   scripts/server_menu.sh survival start     # sobrevivencia: sobe sem rebuild
#   scripts/server_menu.sh tdm restart        # recria o container
#   scripts/server_menu.sh tdm stop           # derruba SO o mata-mata
#   scripts/server_menu.sh stop               # derruba tudo
#   scripts/server_menu.sh logs               # segue o log de tudo que esta no ar
#   scripts/server_menu.sh status             # o que esta no ar
#   PVP_BOTS=4 scripts/server_menu.sh tdm up  # mata-mata com 4 bots (teste)
#   CAR_BOT=1 scripts/server_menu.sh survival up  # com bot dirigindo o carro (teste)
#   PORT=32000 scripts/server_menu.sh tdm up  # outra porta (2o servidor)
#   DRY_RUN=1 scripts/server_menu.sh tdm up   # so mostra o comando
#   scripts/server_menu.sh self-test          # testa o script (sem docker)
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

godot_server_bin="dist/box-godot-linux.x86_64"
## Mata-mata sem bots por padrao (jogo de verdade). PVP_BOTS=N pede bots de teste.
default_pvp_bots="${PVP_BOTS:-0}"
## Bot dirigindo o carro no servidor local (so para testar a rede do veiculo).
## DESLIGADO por padrao: no play normal ninguem ocupa o carro. CAR_BOT=N liga em
## ate N carros.
default_car_bot="${CAR_BOT:-0}"
## Porta unica de todos os modos, igual ao compose.yaml. Na VPS so 27015/udp e
## 27016/udp estao abertas no firewall: um modo numa porta propria nao recebia
## conexao nenhuma. Como dividem a porta, os modos nao rodam juntos — subir um
## derruba o outro, que e a escolha que este menu oferece.
default_port=27015
## Modos conhecidos, na ordem em que aparecem no menu.
all_modes=(survival tdm classic)

usage() {
	cat <<'TXT'
Uso: scripts/server_menu.sh [modo] [acao]

  modo: survival | tdm | classic  (o que subir; 'pvp' e apelido de 'tdm')
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

# Nome do servico/profile no compose. 'pvp' continua valendo como apelido de
# 'tdm' porque a flag do jogo e --pvp e os scripts antigos usam esse nome.
canonical_mode() {
	local mode="$1"
	case "$mode" in
		survival | classic) echo "$mode" ;;
		tdm | pvp) echo "tdm" ;;
		*) die "modo desconhecido: '$mode' (esperado 'survival', 'tdm' ou 'classic')" ;;
	esac
}

require_action() {
	local action="$1"
	case "$action" in
		up | start | restart | stop | logs | status | self-test) ;;
		*) die "acao desconhecida: '$action' (esperado up|start|restart|stop|logs|status|self-test)" ;;
	esac
}

# Exporta as variaveis que o compose le para o modo pedido. Cada modo tem as
# suas (SURVIVAL_*, TDM_*, CLASSIC_*), entao subir um nao mexe no outro.
export_mode_env() {
	local mode="$1"
	[[ "$default_car_bot" =~ ^[0-9]+$ ]] || die "CAR_BOT invalido: '$default_car_bot' (esperado inteiro >= 0)"
	case "$mode" in
		survival)
			export SURVIVAL_CAR_BOT="$default_car_bot"
			export SURVIVAL_NAME="${SERVER_NAME:-}"
			;;
		tdm)
			[[ "$default_pvp_bots" =~ ^[0-9]+$ ]] || die "PVP_BOTS invalido: '$default_pvp_bots' (esperado inteiro >= 0)"
			export TDM_BOTS="$default_pvp_bots"
			export TDM_NAME="${SERVER_NAME:-}"
			;;
		classic)
			export CLASSIC_NAME="${SERVER_NAME:-}"
			;;
	esac
	if [[ -n "${PORT:-}" ]]; then
		[[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT invalido: '$PORT' (esperado inteiro)"
		# Porta unica para todos os modos: abrir outra exige liberar na VPS.
		export GAME_SERVER_PORT="$PORT"
	fi
}

# Prefixo com as variaveis do modo, para o dry-run mostrar exatamente o comando
# que subiria (e para o log deixar claro o que foi escolhido).
mode_env_prefix() {
	local prefix=""
	local name
	for name in GAME_SERVER_PORT SURVIVAL_CAR_BOT SURVIVAL_NAME TDM_BOTS TDM_NAME CLASSIC_NAME; do
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

port_of() {
	echo "${PORT:-$default_port}"
}


## Derruba os OUTROS modos antes de subir um: todos usam a mesma porta, entao
## sem isso o docker recusa com "port is already allocated" e o usuario fica sem
## saber que era o modo anterior ainda no ar.
stop_other_modes() {
	local keep="$1"
	local mode
	for mode in "${all_modes[@]}"; do
		if [[ "$mode" != "$keep" ]]; then
			compose --profile "$mode" stop "$mode"
		fi
	done
}

action_up() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	stop_other_modes "$mode"
	compose --profile "$mode" up -d --build "$mode"
	announce "$mode"
}

action_start() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	stop_other_modes "$mode"
	compose --profile "$mode" up -d "$mode"
	announce "$mode"
}

action_restart() {
	local mode="$1"
	require_docker
	export_mode_env "$mode"
	stop_other_modes "$mode"
	compose --profile "$mode" up -d --force-recreate "$mode"
	announce "$mode"
}

## Sem modo derruba TUDO; com modo derruba so aquele container (os outros modos
## seguem no ar, que e o ponto de ter um container por modo).
action_stop() {
	local mode="${1:-}"
	require_docker
	if [[ -z "$mode" ]]; then
		compose --profile survival --profile tdm --profile classic down
		echo "todos os modos parados"
		return 0
	fi
	compose --profile "$mode" stop "$mode"
	echo "modo '$mode' parado"
}

action_logs() {
	local mode="${1:-}"
	require_docker
	if [[ -z "$mode" ]]; then
		compose --profile survival --profile tdm --profile classic logs -f --tail=80
		return 0
	fi
	compose --profile "$mode" logs -f --tail=80 "$mode"
}

action_status() {
	require_docker
	compose --profile survival --profile tdm --profile classic ps
}

run_without_mode() {
	local action="$1"
	case "$action" in
		stop) action_stop ;;
		logs) action_logs ;;
		status) action_status ;;
	esac
}

mode_label() {
	local mode="$1"
	case "$mode" in
		survival) echo "sobrevivencia (zumbis, hordas)" ;;
		classic) echo "classico (zumbis, sem progressao de onda)" ;;
		tdm)
			if [[ "$default_pvp_bots" == "0" ]]; then
				echo "mata-mata por times (sem bots)"
			else
				echo "mata-mata por times (${default_pvp_bots} bots)"
			fi
			;;
	esac
}

announce() {
	local mode="$1"
	local port
	port="$(port_of "$mode")"
	echo
	echo "no ar: $(mode_label "$mode") | porta $port | container box-godot-$mode"
	echo "conectar: $godot_server_bin -- --join=127.0.0.1 --server-port=$port"
	echo "log:      scripts/server_menu.sh $mode logs"
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

	output="$(DRY_RUN=1 "$0" tdm up)"
	check_contains "$output" "--profile tdm" "tdm up escolhe o profile do mata-mata"
	check_contains "$output" "TDM_BOTS=0" "tdm up sobe SEM bots por padrao"
	check_contains "$output" "--build" "tdm up rebuilda a imagem"
	check_contains "$output" "server-port=27015" "mata-mata na porta aberta da VPS"
	check_contains "$output" "stop survival" "subir o mata-mata derruba a sobrevivencia"

	output="$(DRY_RUN=1 "$0" pvp up)"
	check_contains "$output" "--profile tdm" "'pvp' continua valendo como apelido de 'tdm'"

	output="$(DRY_RUN=1 PVP_BOTS=4 "$0" tdm start)"
	check_contains "$output" "TDM_BOTS=4" "PVP_BOTS=4 pede bots de teste"
	if [[ "$output" == *"--build"* ]]; then
		echo "FALHA: tdm start nao pode rebuildar"
		failures=$((failures + 1))
	else
		echo "PASS: tdm start nao rebuilda"
	fi

	output="$(DRY_RUN=1 "$0" survival up)"
	check_contains "$output" "--profile survival" "survival up escolhe o profile da sobrevivencia"
	check_contains "$output" "server-port=27015" "sobrevivencia na porta aberta da VPS"
	check_contains "$output" "stop tdm" "subir a sobrevivencia derruba o mata-mata"
	if [[ "$output" == *"TDM_BOTS"* ]]; then
		echo "FALHA: subir a sobrevivencia nao pode mexer nas variaveis do mata-mata"
		failures=$((failures + 1))
	else
		echo "PASS: um modo nao mexe nas variaveis do outro"
	fi

	output="$(DRY_RUN=1 "$0" classic up)"
	check_contains "$output" "--profile classic" "classic up escolhe o profile do classico"
	check_contains "$output" "server-port=27015" "classico na porta aberta da VPS"

	output="$(DRY_RUN=1 PORT=32000 "$0" survival start)"
	check_contains "$output" "server-port=32000" "PORT alternativo respeitado"
	check_contains "$output" "GAME_SERVER_PORT=32000" "PORT alternativo chega no compose"

	output="$(DRY_RUN=1 "$0" tdm stop)"
	check_contains "$output" "stop tdm" "parar um modo so derruba aquele container"

	output="$(DRY_RUN=1 "$0" status)"
	check_contains "$output" "ps" "status funciona sem escolher modo"

	if "$0" zumbi up >/dev/null 2>&1; then
		echo "FALHA: modo invalido deveria sair com erro"
		failures=$((failures + 1))
	else
		echo "PASS: modo invalido recusado"
	fi
	if "$0" tdm voar >/dev/null 2>&1; then
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
		echo "=== servidor local (box_godot) — um container por modo ==="
		echo "todos os modos usam a porta $(port_of) (a aberta na VPS); subir um derruba o outro"
		echo "1) sobrevivencia  - rebuild + subir"
		echo "2) mata-mata TDM  - rebuild + subir   ($(mode_label tdm))"
		echo "3) classico       - rebuild + subir"
		echo "4) sobrevivencia  - subir sem rebuild"
		echo "5) mata-mata TDM  - subir sem rebuild"
		echo "6) parar TUDO"
		echo "7) ver log (segue, Ctrl+C sai)"
		echo "8) status"
		echo "9) sair"
		local choice=""
		if ! read -rp "escolha: " choice; then
			echo
			return 0
		fi
		case "$choice" in
			1) action_up survival ;;
			2) action_up tdm ;;
			3) action_up classic ;;
			4) action_start survival ;;
			5) action_start tdm ;;
			6) action_stop ;;
			7) action_logs ;;
			8) action_status ;;
			9) return 0 ;;
			"") ;;
			*) echo "opcao invalida: '$choice' (esperado 1 a 9)" ;;
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
	# Acoes que nao dependem de modo: parar/ver log/status valem sem escolher.
	case "$mode" in
		stop | logs | status)
			run_without_mode "$mode"
			return 0
			;;
	esac
	mode="$(canonical_mode "$mode")"
	action="${action:-up}"
	require_action "$action"
	case "$action" in
		up) action_up "$mode" ;;
		start) action_start "$mode" ;;
		restart) action_restart "$mode" ;;
		stop) action_stop "$mode" ;;
		logs) action_logs "$mode" ;;
		status) action_status ;;
		self-test) self_test ;;
	esac
}

main "$@"
