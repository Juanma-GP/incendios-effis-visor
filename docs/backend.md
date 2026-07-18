# Backend (legacy, ya no lo usa el frontend)

API ligera en FastAPI (`backend/main.py`, deps en `backend/requirements.txt`,
instaladas en el venv raíz `.venv/`). Se usó como capa entre la tabla
`incendios` y el frontend antes de migrar a Supabase. Desde que el
[frontend](frontend.md) llama directamente a la función RPC `get_fires` de
Supabase vía `supabase-js`, este backend ya no hace falta para que el visor
funcione — se conserva por si resulta útil como referencia o para volver a
apuntar contra la Pi.

## Endpoints

- `GET /api/fires?iso2=ES,PT&year=2023` — devuelve una `FeatureCollection`
  GeoJSON (vía `ST_AsGeoJSON` + `json_build_object`), con propiedades
  `id`, `year` (extraído de `initialdate`), `iso2`, `country`, `admlvl1/2/3`,
  `area_ha`, `initialdate`, `finaldate`. Ambos parámetros son opcionales.
- `GET /api/years?iso2=ES,PT` — lista de años distintos disponibles para los
  países dados. Equivalente a la función RPC `get_years` de Supabase (ver
  [database.md](database.md)), que es la que usa el frontend actual.

## Configuración

Variables de entorno para la conexión a Postgres: `PGHOST` (default
`localhost`), `PGPORT` (5432), `PGDATABASE` (`incendios_db`), `PGUSER`
(`kraken`), `PGPASSWORD` (obligatoria, sin default).

```bash
PGHOST=<IP_PI> PGPASSWORD=<pass> ./.venv/bin/uvicorn backend.main:app --reload --port 8000
```

