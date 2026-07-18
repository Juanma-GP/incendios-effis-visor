#!/usr/bin/env python3
"""Copia la tabla incendios desde el Postgres origen (Raspberry Pi) a Supabase.

No reprocesa el GeoJSON: lee las filas ya cargadas (incluida la geometría, en
formato EWKB hexadecimal) y las inserta tal cual en el destino.
"""
import argparse

import psycopg2
from psycopg2.extras import execute_values

PROPERTY_COLUMNS = [
    "id", "initialdate", "finaldate", "area_ha", "iso2", "iso3", "country",
    "admlvl1", "admlvl2", "admlvl3", "admlvl5", "map_source",
    "broadleaved_forest_percent", "coniferous_forest_percent", "mixed_forest_percent",
    "sclerophillous_vegetation_percent", "transitional_vegetation_percent",
    "other_natural_percent", "agriculture_percent", "artificial_percent",
    "other_percent", "natura2k_percent",
]

SELECT_SQL = f"""
    SELECT {", ".join(PROPERTY_COLUMNS)}, encode(ST_AsEWKB(geom), 'hex') AS geom_hex
    FROM incendios
    ORDER BY id
"""

INSERT_SQL = f"""
    INSERT INTO incendios ({", ".join(PROPERTY_COLUMNS)}, geom)
    VALUES %s
    ON CONFLICT (id) DO NOTHING
"""

VALUE_TEMPLATE = (
    "(" + ", ".join(["%s"] * len(PROPERTY_COLUMNS)) + ", ST_GeomFromEWKB(decode(%s, 'hex')))"
)


def connect(host, port, dbname, user, password):
    return psycopg2.connect(host=host, port=port, dbname=dbname, user=user, password=password)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-host", required=True)
    parser.add_argument("--source-port", default=5432, type=int)
    parser.add_argument("--source-dbname", default="incendios_db")
    parser.add_argument("--source-user", default="kraken")
    parser.add_argument("--source-password", required=True)

    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", default=5432, type=int)
    parser.add_argument("--target-dbname", default="postgres")
    parser.add_argument("--target-user", default="postgres")
    parser.add_argument("--target-password", required=True)

    parser.add_argument("--batch-size", default=500, type=int)
    args = parser.parse_args()

    source = connect(args.source_host, args.source_port, args.source_dbname,
                      args.source_user, args.source_password)
    target = connect(args.target_host, args.target_port, args.target_dbname,
                      args.target_user, args.target_password)

    try:
        with source.cursor(name="incendios_export") as src_cur, target.cursor() as tgt_cur:
            src_cur.itersize = args.batch_size
            src_cur.execute(SELECT_SQL)

            inserted = 0
            while True:
                rows = src_cur.fetchmany(args.batch_size)
                if not rows:
                    break
                execute_values(tgt_cur, INSERT_SQL, rows, template=VALUE_TEMPLATE)
                inserted += len(rows)
                print(f"  {inserted} filas copiadas")

        target.commit()
        print(f"OK, {inserted} filas copiadas a Supabase.")
    finally:
        source.close()
        target.close()


if __name__ == "__main__":
    main()
