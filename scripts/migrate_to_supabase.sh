#!/usr/bin/env bash
# Copia la tabla incendios desde tu Postgres de la Raspberry Pi a Supabase.
#
# Uso:
#   SOURCE_HOST='<IP de la Pi>' SOURCE_PASSWORD='postgis_2026' ./scripts/migrate_to_supabase.sh
#
# La contraseña de Supabase se lee del fichero .ñ.txt (no se pide ni se
# escribe en ningún sitio de este script).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SOURCE_HOST:?Falta SOURCE_HOST (IP de la Raspberry Pi)}"
: "${SOURCE_PASSWORD:?Falta SOURCE_PASSWORD (password del usuario kraken en la Pi)}"

TARGET_PASSWORD_FILE=".ñ.txt"
if [ ! -f "$TARGET_PASSWORD_FILE" ]; then
  echo "No encuentro $TARGET_PASSWORD_FILE con la contraseña de Supabase" >&2
  exit 1
fi
TARGET_PASSWORD="$(cat "$TARGET_PASSWORD_FILE")"

./.venv/bin/python scripts/copy_to_supabase.py \
  --source-host "$SOURCE_HOST" \
  --source-password "$SOURCE_PASSWORD" \
  --target-host "aws-0-eu-west-1.pooler.supabase.com" \
  --target-user "postgres.qohghmezubkfckukbacz" \
  --target-password "$TARGET_PASSWORD"
