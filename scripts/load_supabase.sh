#!/usr/bin/env bash
# Carga cualquier .json de la raíz del proyecto que tenga forma de
# exportación EFFIS (lo valida load_incendios.py por contenido, no por
# nombre de fichero) directamente en Supabase. Este es el canal oficial
# para nuevas descargas desde 2026-07-16: la Raspberry Pi ya no es el
# destino de las cargas nuevas, solo queda como copia histórica.
#
# La contraseña de Supabase se lee de .ñ.txt, nunca se escribe aquí.
#
# Uso:
#   ./scripts/load_supabase.sh
set -uo pipefail
cd "$(dirname "$0")/.."

TARGET_PASSWORD_FILE=".ñ.txt"
if [ ! -f "$TARGET_PASSWORD_FILE" ]; then
  echo "No encuentro $TARGET_PASSWORD_FILE con la contraseña de Supabase" >&2
  exit 1
fi
TARGET_PASSWORD="$(cat "$TARGET_PASSWORD_FILE")"

SUPABASE_HOST="aws-0-eu-west-1.pooler.supabase.com"
SUPABASE_PORT="5432"
SUPABASE_DB="postgres"
SUPABASE_USER="postgres.qohghmezubkfckukbacz"

shopt -s nullglob
json_files=(*.json)
if [ ${#json_files[@]} -eq 0 ]; then
  echo "No hay ficheros .json en la raíz del proyecto." >&2
  exit 1
fi

for f in "${json_files[@]}"; do
  echo "=== $f ==="
  if ./.venv/bin/python load_incendios.py "$f" \
    --host "$SUPABASE_HOST" \
    --port "$SUPABASE_PORT" \
    --dbname "$SUPABASE_DB" \
    --user "$SUPABASE_USER" \
    --password "$TARGET_PASSWORD"; then
    echo "  -> cargado en Supabase"
  else
    echo "  -> omitido (no tiene forma de exportación EFFIS o falló la carga)"
  fi
done
