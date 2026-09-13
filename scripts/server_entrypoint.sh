#!/usr/bin/env bash
set -euo pipefail

world_seed="${GAME_SERVER_WORLD_SEED:-}"
if [[ -z "$world_seed" ]]; then
	container_checksum="$(cksum /etc/hostname)"
	world_seed="${container_checksum%% *}"
fi

printf 'World seed: %s\n' "$world_seed"
exec godot --headless --path /game -- "$@" "--world-seed=$world_seed"
