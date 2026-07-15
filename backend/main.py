import os
from typing import Optional

import psycopg2
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Incendios API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_connection():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", 5432),
        dbname=os.environ.get("PGDATABASE", "incendios_db"),
        user=os.environ.get("PGUSER", "kraken"),
        password=os.environ["PGPASSWORD"],
    )


FIRES_SQL_TEMPLATE = """
    SELECT json_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(json_agg(feature), '[]'::json)
    )
    FROM (
        SELECT json_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(geom)::json,
            'properties', json_build_object(
                'id', id,
                'year', EXTRACT(YEAR FROM initialdate)::int,
                'iso2', iso2,
                'country', country,
                'admlvl1', admlvl1,
                'admlvl2', admlvl2,
                'admlvl3', admlvl3,
                'area_ha', area_ha,
                'initialdate', initialdate,
                'finaldate', finaldate
            )
        ) AS feature
        FROM incendios
        {where}
    ) f
"""


@app.get("/api/fires")
def get_fires(
    iso2: Optional[str] = Query(None, description="Códigos de país separados por coma, ej. ES,PT"),
    year: Optional[int] = Query(None, description="Año de initialdate"),
):
    conditions = []
    params = []

    if iso2:
        codes = [c.strip().upper() for c in iso2.split(",") if c.strip()]
        conditions.append("iso2 = ANY(%s)")
        params.append(codes)

    if year is not None:
        conditions.append("EXTRACT(YEAR FROM initialdate) = %s")
        params.append(year)

    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    sql = FIRES_SQL_TEMPLATE.format(where=where)

    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        (result,) = cur.fetchone()
    return result


@app.get("/api/years")
def get_years(iso2: Optional[str] = Query(None)):
    conditions = []
    params = []
    if iso2:
        codes = [c.strip().upper() for c in iso2.split(",") if c.strip()]
        conditions.append("iso2 = ANY(%s)")
        params.append(codes)
    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    sql = f"""
        SELECT DISTINCT EXTRACT(YEAR FROM initialdate)::int AS year
        FROM incendios
        {where}
        ORDER BY year
    """
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        years = [row[0] for row in cur.fetchall()]
    return years
