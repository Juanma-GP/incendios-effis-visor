#!/usr/bin/env python3
"""Llama a rebuild_fire_zones() en Supabase.

Operación pesada (TRUNCATE + ST_ClusterDBSCAN sobre toda la tabla
incendios), por eso no es un trigger: se llama una sola vez, al final de
cargar todos los ficheros nuevos en scripts/load_supabase.sh.
"""
import argparse

import psycopg2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default=5432, type=int)
    parser.add_argument("--dbname", default="incendios_db")
    parser.add_argument("--user", default="kraken")
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    conn = psycopg2.connect(
        host=args.host, port=args.port, dbname=args.dbname,
        user=args.user, password=args.password,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT rebuild_fire_zones();")
        conn.commit()
        print("OK, fire_zones recalculada.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
