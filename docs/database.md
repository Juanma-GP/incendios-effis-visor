# Base de datos

## Estado actual: Postgres+PostGIS en Raspberry Pi

- Postgres 16 + PostGIS 3.4 corriendo en Docker en una Raspberry Pi 5
  (arch `linux/arm64/v8`), imagen `imresamu/postgis:16-3.4` (el `postgis/postgis`
  oficial solo publica `amd64`, no sirve en la Pi).
- Contenedor: `postgis`. Volumen de datos en
  `/mnt/immich-data/postgis/data` (comparte disco de 4TB con Immich, pero es
  una instancia y base de datos independientes, no son los mismos datos).
- Base de datos: `incendios_db`. Usuario: `kraken`.
  **Nota:** la contraseña no se guarda en este repo; se pasa por variable de
  entorno o flag (`--password` en `load_incendios.py`, `PGPASSWORD` para la
  API) al ejecutar scripts/backend.
- El usuario se conecta a la Pi por SSH; Claude no tiene acceso directo, así
  que los comandos para ejecutar allí se entregan como texto para que el
  usuario los corra y pegue el resultado.

## Esquema

Tabla `incendios`: una fila por perímetro de incendio, `geom` en SRID 4326
(se transforma desde el 3035 original al cargar).

```sql
CREATE TABLE incendios (
    id                                  integer PRIMARY KEY,
    initialdate                        timestamp,
    finaldate                          timestamp,
    area_ha                            numeric,
    iso2                               text,
    iso3                               text,
    country                            text,
    admlvl1                            text,
    admlvl2                            text,
    admlvl3                            text,
    admlvl5                            text,
    map_source                         text,
    broadleaved_forest_percent         numeric,
    coniferous_forest_percent          numeric,
    mixed_forest_percent               numeric,
    sclerophillous_vegetation_percent  numeric,
    transitional_vegetation_percent    numeric,
    other_natural_percent              numeric,
    agriculture_percent                numeric,
    artificial_percent                 numeric,
    other_percent                      numeric,
    natura2k_percent                   numeric,
    geom                               geometry(MultiPolygon, 4326)
);

CREATE INDEX incendios_geom_idx ON incendios USING GIST (geom);
```

Ver [data.md](data.md) para el detalle de qué contiene cada columna.

## Índices

- GIST sobre `geom` (creado).
- Pendiente añadir btree sobre `iso2` e `initialdate` si el filtrado por
  país/fecha se vuelve lento. Con ~30k filas totales (dos extracciones
  cargadas) no hace falta TimescaleDB — es una herramienta pensada para
  series temporales de alto volumen/ingesta continua, innecesaria aquí.

## Carga de datos

`load_incendios.py` (usa el venv en `.venv/`):

- Reconstruye la geometría manualmente a WKT, sin `shapely` ni GDAL.
- Reproyecta en la propia consulta SQL con
  `ST_Transform(ST_SetSRID(ST_GeomFromText(...), 3035), 4326)`.
- Cuidado con los campos de fecha: `initialdate`/`finaldate` a veces
  incluyen fracción de segundos (`.317`) — hay que detectarlo antes de
  aplicar el formato correcto a `strptime`.
- Usa `ON CONFLICT (id) DO NOTHING`, así que cargar el mismo fichero dos
  veces (o ficheros con rangos de fechas solapados) no duplica filas.

```bash
./.venv/bin/python load_incendios.py <fichero>.json --host <IP_PI> --password <pass>
```

## Plan futuro: migración a Supabase

Idea en evaluación para poder alojar el frontend en GitHub Pages (solo
estático, sin backend propio): mover los datos a Supabase (Postgres+PostGIS
gestionado, con API REST automática vía PostgREST).

- Elimina la necesidad de mantener el backend FastAPI propio: se define una
  función SQL en Supabase que devuelva GeoJSON y se llama directamente desde
  el frontend estático con el cliente `supabase-js`.
- Los datos quedarían consultables públicamente vía la API key `anon` de
  Supabase — asumible porque es un dataset público de la UE (EFFIS), no hay
  problema de privacidad. Si hiciera falta restringir algo, se controla con
  Row Level Security.
- El tier gratuito de Supabase (500MB de DB, pausa tras inactividad
  prolongada) sobra para el volumen de datos actual (~30k filas).
- Pendiente de decidir/implementar, ver roadmap en el `CLAUDE.md` raíz.
