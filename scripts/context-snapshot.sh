#!/usr/bin/env bash
# context-snapshot.sh — snapshot estándar del entorno local para adjuntar a
# cualquier propuesta que se pase entre agentes en fase de diseño.
#
# SEGURO POR DEFECTO: nunca vuelca valores de .env, tokens, passwords, claves
# SSH, ni datos de negocio. Solo muestra NOMBRES de variables cuando aplica,
# nunca sus valores.
#
# Uso: bash scripts/context-snapshot.sh
# Uso con VPS (requiere alias SSH ya configurado en ~/.ssh/config):
#   bash scripts/context-snapshot.sh --vps <alias-ssh>

set -uo pipefail

echo "=== context-snapshot: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo ""

echo "--- Sistema local ---"
uname -a
echo ""

echo "--- Lenguajes / runtimes ---"
command -v python3 &>/dev/null && python3 --version
command -v node &>/dev/null && node --version
command -v docker &>/dev/null && docker --version
echo ""

echo "--- Git ---"
git rev-parse --show-toplevel 2>/dev/null
git branch --show-current 2>/dev/null
git remote -v 2>/dev/null | sed -E 's#(https://)[^@]+@#\1***@#'  # oculta credenciales embebidas si las hubiera
echo ""

echo "--- Docker (si aplica) ---"
if command -v docker &>/dev/null; then
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null
  echo ""
  docker network ls --format 'table {{.Name}}\t{{.Driver}}' 2>/dev/null
fi
echo ""

echo "--- Variables de entorno relevantes (solo NOMBRES, nunca valores) ---"
if [ -f .env.example ]; then
  echo "Definidas en .env.example:"
  grep -oE '^[A-Z_]+=' .env.example | sed 's/=$//'
fi
echo ""

if [ "${1:-}" = "--vps" ] && [ -n "${2:-}" ]; then
  echo "--- VPS ($2) ---"
  ssh "$2" 'echo "uname:"; uname -a; \
    echo "python3:"; python3 --version 2>/dev/null; \
    echo "docker:"; docker --version 2>/dev/null; \
    echo "docker ps:"; docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null; \
    echo "docker networks:"; docker network ls --format "table {{.Name}}\t{{.Driver}}" 2>/dev/null' \
    2>/dev/null || echo "⚠️  No se pudo conectar por SSH a $2 — verifica el alias en ~/.ssh/config"
fi

echo ""
echo "=== fin del snapshot ==="
