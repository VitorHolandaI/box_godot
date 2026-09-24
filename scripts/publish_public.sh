#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
# Publica o projeto no repositorio PUBLICO do GitHub a partir de um clone
# espelho, com o historico limpo: sem binarios de release e sem IPs de
# infraestrutura (nem no conteudo antigo, nem nas mensagens de commit).
#
# O repositorio publico NUNCA recebe push direto do repo de trabalho: o
# historico reescrito tem outros SHAs, entao um `git push` normal e recusado.
# Rode este script para publicar/atualizar.
#
# Uso:
#   scripts/publish_public.sh                 # publica (pede confirmacao)
#   scripts/publish_public.sh --dry-run       # so mostra o plano
#   PUBLIC_REMOTE=git@github.com:user/repo.git scripts/publish_public.sh
#   PUBLISH_IP_MAP=/caminho/mapa.txt scripts/publish_public.sh
#
# O mapa de IPs fica FORA do repositorio (gitignored), no formato
# `antigo==>novo` uma linha por IP, porque ele proprio contem os valores reais.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_remote="${PUBLIC_REMOTE:-git@github.com:VitorHolandaI/box_godot.git}"
ip_map_file="${PUBLISH_IP_MAP:-$project_dir/.publish-ip-map.txt}"
filter_repo="${FILTER_REPO_BIN:-git-filter-repo}"
dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

die() {
	echo "erro: $1" >&2
	exit 1
}

# Sem git-filter-repo instalado, baixa o script oficial (arquivo unico, sem
# instalacao) para o cache do usuario. FILTER_REPO_BIN sempre manda.
ensure_filter_repo() {
	if [[ "$filter_repo" == */* ]]; then
		[[ -x "$filter_repo" ]] || die "FILTER_REPO_BIN nao e executavel: '$filter_repo'"
		return
	fi
	if command -v "$filter_repo" >/dev/null 2>&1; then
		return
	fi
	[[ "$filter_repo" == "git-filter-repo" ]] || die "git-filter-repo nao encontrado (esperado no PATH ou em FILTER_REPO_BIN): '$filter_repo'"
	local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/box-godot"
	local cached="$cache_dir/git-filter-repo"
	if [[ ! -x "$cached" ]]; then
		command -v curl >/dev/null 2>&1 || die "curl nao encontrado para baixar o git-filter-repo (instale com 'pacman -S git-filter-repo' ou defina FILTER_REPO_BIN)"
		mkdir -p "$cache_dir"
		echo ">> baixando git-filter-repo (nao instalado) para $cached"
		curl -fsSL -o "$cached" "https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo" \
			|| die "falhou o download do git-filter-repo"
		chmod +x "$cached"
	fi
	filter_repo="$cached"
}

require_tools() {
	command -v git >/dev/null 2>&1 || die "git nao encontrado no PATH (esperado o binario 'git')"
	ensure_filter_repo
}

require_ip_map() {
	[[ -f "$ip_map_file" ]] || die "mapa de IPs nao encontrado em '$ip_map_file' (crie com linhas 'antigo==>novo'; veja .publish-ip-map.example.txt)"
	local malformed
	malformed="$(grep -vE '^[^=]+==>[^=]+$' "$ip_map_file" | head -1 || true)"
	[[ -z "$malformed" ]] || die "linha invalida no mapa de IPs: '$malformed' (esperado 'antigo==>novo')"
}

plan() {
	echo "repo de trabalho : $project_dir"
	echo "destino publico  : $public_remote"
	echo "mapa de IPs      : $ip_map_file"
	echo "remove           : *.x86_64, *.exe, *.pck (binarios de release)"
	echo "troca            : os IPs do mapa, em todo o historico (conteudo e mensagens)"
}

# Confere que nenhum IP do mapa sobrou: pickaxe em todo o historico (conteudo) e
# grep nas mensagens. O pickaxe e o teste certo para string que EXISTIU em algum
# commit — `git grep` commit a commit custaria centenas de processos.
verify_clean() {
	local mirror="$1"
	local binarios
	binarios="$(cd "$mirror" && git rev-list --objects --all | grep -cE '\.(x86_64|exe|pck)$' || true)"
	[[ "$binarios" == "0" ]] || die "ainda ha $binarios binario(s) no historico reescrito"

	local mencoes_claude
	mencoes_claude="$(cd "$mirror" && git log --all --format='%B' | grep -ci 'claude' || true)"
	[[ "$mencoes_claude" == "0" ]] || die "historico reescrito ainda cita Claude em $mencoes_claude linha(s)"
	echo "   ok: nenhuma mencao a Claude nas mensagens"

	local arquivo_claude
	arquivo_claude="$(cd "$mirror" && git rev-list --objects --all | grep -c 'CLAUDE.md' || true)"
	[[ "$arquivo_claude" == "0" ]] || die "CLAUDE.md ainda existe no historico reescrito"
	echo "   ok: CLAUDE.md fora do historico"

	local mensagens
	mensagens="$(cd "$mirror" && git log --all --format='%B')"
	local linha ip hits
	while IFS= read -r linha; do
		ip="${linha%%==>*}"
		[[ -n "$ip" ]] || continue
		if grep -qF "$ip" <<<"$mensagens"; then
			die "mensagem de commit ainda cita '$ip'"
		fi
		hits="$(cd "$mirror" && git log --all --oneline -S"$ip" | wc -l)"
		[[ "$hits" == "0" ]] || die "conteudo do historico ainda cita '$ip' em $hits commit(s)"
		echo "   ok: '$ip' nao aparece no historico"
	done < "$ip_map_file"
}

publish() {
	local mirror
	mirror="$(mktemp -d /tmp/publish-public.XXXXXX)/mirror.git"
	echo ">> clonando espelho de $project_dir"
	git clone --mirror -q "$project_dir" "$mirror"

	echo ">> reescrevendo historico (filter-repo)"
	(
		cd "$mirror"
		"$filter_repo" --force \
			--invert-paths --path-glob '*.x86_64' --path-glob '*.exe' --path-glob '*.pck' \
			--path CLAUDE.md \
			--replace-text "$ip_map_file" \
			--replace-message "$ip_map_file" \
			--message-callback '
lines = [line for line in message.decode("utf-8", "replace").splitlines()
         if "claude" not in line.lower()]
return ("\n".join(lines).rstrip() + "\n").encode("utf-8")
' >/dev/null
	)

	echo ">> conferindo o resultado"
	verify_clean "$mirror"

	echo ">> enviando para $public_remote"
	(
		cd "$mirror"
		git remote add public "$public_remote"
		git push --force public --all
		git push --force public --tags
	)
	echo "publicado em ${public_remote#git@github.com:}"
}

require_tools
require_ip_map
plan
if [[ "$dry_run" == "1" ]]; then
	echo "(dry-run: nada foi clonado nem enviado)"
	exit 0
fi
read -rp "publicar em $public_remote? [s/N] " answer
[[ "$answer" == "s" || "$answer" == "S" ]] || die "cancelado pelo usuario"
publish
