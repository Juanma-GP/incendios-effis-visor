# Backend

API ligera en FastAPI (`backend/main.py`, deps en `backend/requirements.txt`,
instaladas en el venv raíz `.venv/`), pensada como capa entre la tabla
`incendios` (ver [database.md](database.md)) y el frontend.

## Endpoints

- `GET /api/fires?iso2=ES,PT&year=2023` — devuelve una `FeatureCollection`
  GeoJSON (vía `ST_AsGeoJSON` + `json_build_object`), con propiedades
  `id`, `year` (extraído de `initialdate`), `iso2`, `country`, `admlvl1/2/3`,
  `area_ha`, `initialdate`, `finaldate`. Ambos parámetros son opcionales.
- `GET /api/years?iso2=ES,PT` — lista de años distintos disponibles para los
  países dados. **Nota:** el frontend actual ya no usa este endpoint (deriva
  los años de las features que descarga de `/api/fires`, ver
  [frontend.md](frontend.md)), pero se mantiene por si resulta útil.

## Configuración

Variables de entorno para la conexión a Postgres: `PGHOST` (default
`localhost`), `PGPORT` (5432), `PGDATABASE` (`incendios_db`), `PGUSER`
(`kraken`), `PGPASSWORD` (obligatoria, sin default).

```bash
PGHOST=<IP_PI> PGPASSWORD=<pass> ./.venv/bin/uvicorn backend.main:app --reload --port 8000
```

## Plan futuro

Si se migra a Supabase (ver [database.md](database.md)), este backend
dejaría de ser necesario: PostgREST + una función SQL en Supabase cubrirían
el mismo rol, permitiendo que el frontend sea 100% estático (GitHub Pages).
