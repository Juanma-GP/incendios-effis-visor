#!/usr/bin/env bash
# Descomprime cualquier .zip de la raíz del proyecto (tal cual llega por
# email de EFFIS), carga en Supabase cualquier .json resultante que tenga
# forma de exportación EFFIS (lo valida load_incendios.py por contenido, no
# por nombre de fichero), y al terminar borra el/los .zip y los .json ya
# cargados — son datos descargables de nuevo desde EFFIS (por eso están en
# .gitignore), no hace falta conservarlos en local. No se toca ningún otro
# fichero (p.ej. los .readme.txt sí se conservan). Este es el canal oficial
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
zip_files=(*.zip)
for z in "${zip_files[@]}"; do
  echo "=== Descomprimiendo $z ==="
  unzip -o -q "$z"
done

json_files=(*.json)
if [ ${#json_files[@]} -eq 0 ]; then
  echo "No hay ficheros .json en la raíz del proyecto." >&2
  exit 1
fi

any_loaded=0
for f in "${json_files[@]}"; do
  echo "=== $f ==="
  if ./.venv/bin/python load_incendios.py "$f" \
    --host "$SUPABASE_HOST" \
    --port "$SUPABASE_PORT" \
    --dbname "$SUPABASE_DB" \
    --user "$SUPABASE_USER" \
    --password "$TARGET_PASSWORD"; then
    echo "  -> cargado en Supabase"
    any_loaded=1
  else
    echo "  -> omitido (no tiene forma de exportación EFFIS o falló la carga)"
  fi
done

# rebuild_fire_zones() es pesada (recorre toda la tabla incendios), por eso
# se llama una sola vez aquí al final, no por cada fichero ni por trigger.
if [ "$any_loaded" -eq 1 ]; then
  echo "=== Recalculando fire_zones ==="
  ./.venv/bin/python scripts/rebuild_fire_zones.py \
    --host "$SUPABASE_HOST" \
    --port "$SUPABASE_PORT" \
    --dbname "$SUPABASE_DB" \
    --user "$SUPABASE_USER" \
    --password "$TARGET_PASSWORD"
fi

# Limpieza: solo los ficheros de datos ya procesados (json + zip), nada más.
echo "=== Limpiando ficheros de datos ==="
rm -f "${json_files[@]}" "${zip_files[@]}"
