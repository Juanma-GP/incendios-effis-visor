#!/usr/bin/env python3
"""Carga el GeoJSON de EFFIS (SRID 3035) en la tabla incendios (SRID 4326)."""
import argparse
import json
from datetime import datetime

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

INSERT_SQL = f"""
    INSERT INTO incendios ({", ".join(PROPERTY_COLUMNS)}, geom)
    VALUES %s
    ON CONFLICT (id) DO NOTHING
"""

VALUE_TEMPLATE = (
    "(" + ", ".join(["%s"] * len(PROPERTY_COLUMNS))
    + ", ST_Transform(ST_SetSRID(ST_GeomFromText(%s), 3035), 4326))"
)


def parse_date(value):
    if value is None:
        return None
    value = value.split("+")[0]
    fmt = "%Y/%m/%d %H:%M:%S.%f" if "." in value else "%Y/%m/%d %H:%M:%S"
    return datetime.strptime(value, fmt)


def multipolygon_to_wkt(coordinates):
    polygons = []
    for polygon in coordinates:
        rings = []
        for ring in polygon:
            points = ", ".join(f"{x} {y}" for x, y in ring)
            rings.append(f"({points})")
        polygons.append("(" + ", ".join(rings) + ")")
    return "MULTIPOLYGON(" + ", ".join(polygons) + ")"


def feature_to_row(feature):
    props = feature["properties"]
    row = []
    for col in PROPERTY_COLUMNS:
        value = props.get(col)
        if col in ("initialdate", "finaldate"):
            value = parse_date(value)
        row.append(value)
    row.append(multipolygon_to_wkt(feature["geometry"]["coordinates"]))
    return tuple(row)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("json_path")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default=5432, type=int)
    parser.add_argument("--dbname", default="incendios_db")
    parser.add_argument("--user", default="kraken")
    parser.add_argument("--password", required=True)
    parser.add_argument("--batch-size", default=500, type=int)
    args = parser.parse_args()

    with open(args.json_path, encoding="utf-8") as f:
        data = json.load(f)
    features = data["features"]
    print(f"Features encontradas: {len(features)}")

    conn = psycopg2.connect(
        host=args.host, port=args.port, dbname=args.dbname,
        user=args.user, password=args.password,
    )
    try:
        with conn.cursor() as cur:
            rows = (feature_to_row(feat) for feat in features)
            batch = []
            inserted = 0
            for row in rows:
                batch.append(row)
                if len(batch) >= args.batch_size:
                    execute_values(cur, INSERT_SQL, batch, template=VALUE_TEMPLATE)
                    inserted += len(batch)
                    print(f"  {inserted}/{len(features)}")
                    batch.clear()
            if batch:
                execute_values(cur, INSERT_SQL, batch, template=VALUE_TEMPLATE)
                inserted += len(batch)
        conn.commit()
        print(f"OK, {inserted} filas insertadas.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
