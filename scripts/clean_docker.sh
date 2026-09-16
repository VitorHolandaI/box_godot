#!/usr/bin/env bash
set -euo pipefail
# Clean total do compose: containers, volumes, imagens locais e orphans
# Uso: bash scripts/clean_docker.sh [--images]

cd "$(dirname "$0")/.."

echo ">> docker compose down -v --remove-orphans"
docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null || true

echo ">> removendo volumes dangling do projeto"
docker volume ls -q | xargs -r docker volume rm 2>/dev/null || true

if [[ "${1:-}" == "--images" ]]; then
  echo ">> removendo imagem box-godot-server:local"
  docker rmi box-godot-server:local 2>/dev/null || true
  docker image prune -f 2>/dev/null || true
fi

echo ">> prune de networks/build cache (opcional)"
docker network prune -f 2>/dev/null || true
docker builder prune -f 2>/dev/null || true

echo "clean ok"
