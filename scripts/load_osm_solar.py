#!/usr/bin/env python3
"""Carga plantas solares (power=plant + plant:source=solar) desde
OpenStreetMap/Overpass API en la tabla solar_plants de Supabase.

Prototipo para comprobar coincidencia espacial con zonas quemadas (ver
CLAUDE.md, roadmap punto 11). Solo se guarda el centro de cada instalación,
no el polígono completo (ver supabase/update_2026-07-26_solar_plants.sql).
"""
import argparse
import json
import re
import sys
import urllib.parse
import urllib.request

import psycopg2
from psycopg2.extras import execute_values

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Bbox que cubre España y Portugal peninsulares (con un poco de margen hacia
# Francia/Marruecos, igual que el dataset de incendios). Se usa bbox en vez
# de area["ISO3166-1"=...] porque el area lookup da timeout en el servidor
# público de Overpass; el bbox es rápido.
BBOX = (36.0, -9.5, 43.8, 3.5)  # south, west, north, east

OVERPASS_QUERY = f"""
[out:json][timeout:180][bbox:{BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]}];
(
  way["power"="plant"]["plant:source"="solar"];
  relation["power"="plant"]["plant:source"="solar"];
);
out tags center;
"""

COLUMNS = [
    "osm_type", "osm_id", "name", "operator", "plant_method",
    "output_electricity", "start_date_raw", "start_year",
]

INSERT_SQL = f"""
    INSERT INTO solar_plants ({", ".join(COLUMNS)}, geom)
    VALUES %s
    ON CONFLICT (osm_type, osm_id) DO UPDATE SET
        {", ".join(f"{col} = EXCLUDED.{col}" for col in COLUMNS if col not in ("osm_type", "osm_id"))},
        geom = EXCLUDED.geom
"""

VALUE_TEMPLATE = (
    "(" + ", ".join(["%s"] * len(COLUMNS))
    + ", ST_SetSRID(ST_GeomFromText(%s), 4326))"
)

YEAR_RE = re.compile(r"(\d{4})")


def fetch_overpass_elements():
    data = urllib.parse.urlencode({"data": OVERPASS_QUERY}).encode("utf-8")
    req = urllib.request.Request(
        OVERPASS_URL,
        data=data,
        headers={"User-Agent": "incendios-effis-visor/1.0 (github.com/Juanma-GP/incendios-effis-visor)"},
    )
    with urllib.request.urlopen(req, timeout=200) as resp:
        payload = json.load(resp)
    return payload["elements"]


def parse_start_year(start_date_raw):
    if not start_date_raw:
        return None
    match = YEAR_RE.search(start_date_raw)
    if not match:
        return None
    year = int(match.group(1))
    if 1900 <= year <= 2100:
        return year
    return None


def element_to_row(el):
    tags = el.get("tags", {})
    center = el.get("center")
    if not center:
        return None
    start_date_raw = tags.get("start_date")
    row = [
        el["type"],
        el["id"],
        tags.get("name"),
        tags.get("operator"),
        tags.get("plant:method"),
        tags.get("plant:output:electricity"),
        start_date_raw,
        parse_start_year(start_date_raw),
    ]
    row.append(f"POINT({center['lon']} {center['lat']})")
    return tuple(row)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default=5432, type=int)
    parser.add_argument("--dbname", default="incendios_db")
    parser.add_argument("--user", default="kraken")
    parser.add_argument("--password", required=True)
    parser.add_argument("--batch-size", default=500, type=int)
    args = parser.parse_args()

    print("Consultando Overpass API...")
    elements = fetch_overpass_elements()
    print(f"Elementos encontrados: {len(elements)}")

    rows = [row for el in elements if (row := element_to_row(el)) is not None]
    skipped = len(elements) - len(rows)
    if skipped:
        print(f"  ({skipped} sin coordenadas 'center', omitidos)", file=sys.stderr)

    conn = psycopg2.connect(
        host=args.host, port=args.port, dbname=args.dbname,
        user=args.user, password=args.password,
    )
    try:
        with conn.cursor() as cur:
            for i in range(0, len(rows), args.batch_size):
                batch = rows[i:i + args.batch_size]
                execute_values(cur, INSERT_SQL, batch, template=VALUE_TEMPLATE)
                print(f"  {min(i + args.batch_size, len(rows))}/{len(rows)}")
        conn.commit()
        print(f"OK, {len(rows)} filas insertadas/actualizadas.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
