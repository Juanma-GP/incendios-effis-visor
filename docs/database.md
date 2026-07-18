# Base de datos

## Estado actual: Supabase (canónica, desde 2026-07-16)

Supabase es la base de datos activa. La Raspberry Pi queda como copia
histórica de cómo se hizo la primera carga, pero **las descargas nuevas de
EFFIS ya no van ahí** — van directas a Supabase con `scripts/load_supabase.sh`
(ver más abajo).

- Proyecto en la región `eu-west-1`. Project URL:
  `https://qohghmezubkfckukbacz.supabase.co`.
- Conexión a Postgres: **usar el Session Pooler**, no la conexión directa.
  La conexión directa (`db.qohghmezubkfckukbacz.supabase.co`) solo tiene
  registro DNS IPv6 (`AAAA`), y muchas redes/resolutores no la resuelven —
  falla con `could not translate host name to address`. El pooler sí
  funciona por IPv4:
  - Host: `aws-0-eu-west-1.pooler.supabase.com`
  - Puerto: `5432` (modo sesión — necesario si algún script usa cursores
    con nombre; el modo transacción en `6543` no los soporta)
  - Usuario: `postgres.qohghmezubkfckukbacz` (nótese el `.<project-ref>`,
    distinto del `postgres` a secas de una conexión directa)
  - Base de datos: `postgres`
- **Contraseña**: vive en el fichero local `.ñ.txt` (en `.gitignore`, nunca
  se commitea). Los scripts la leen de ahí, no se pide por CLI ni se guarda
  en ningún otro sitio del repo.
- Esquema completo (tabla + índices + RLS + funciones RPC) en
  [`supabase/schema.sql`](../supabase/schema.sql) — pensado para un proyecto
  nuevo desde cero. Los cambios posteriores sobre un proyecto ya creado se
  guardan como ficheros de actualización aparte, ej.
  [`supabase/update_2026-07-17_years_perf.sql`](../supabase/update_2026-07-17_years_perf.sql).
- **Row Level Security**: activado. Política de solo lectura pública
  (`SELECT` para el rol `anon`), sin permisos de escritura — necesario
  porque la `anon`/`publishable key` queda embebida en el frontend y es
  visible para cualquiera.
- Función RPC `get_fires(country_codes text[], filter_years int[])`: devuelve
  GeoJSON directamente, pensada para llamarse desde el frontend con
  `supabase-js` sin pasar por un backend propio (ver [frontend.md](frontend.md)
  y [backend.md](backend.md)). Las coordenadas se sirven con
  `ST_AsGeoJSON(geom_simplified, 5)` — 5 decimales (~1m) sobre la columna
  **simplificada**, no la geometría original (ver más abajo, columna
  `geom_simplified`).
- Función RPC `get_years(country_codes text[])`: devuelve solo los años
  distintos disponibles para los países dados, **sin geometría** — se usa
  para poblar el selector de años del frontend sin tener que descargar antes
  todas las geometrías (evita el problema de huevo-y-gallina de "para saber
  qué años hay, necesito los datos completos").

## Histórico: Postgres+PostGIS en Raspberry Pi

Así se hizo la primera carga, antes de migrar a Supabase. Se conserva la
instancia por si hace falta consultar el histórico o repetir el proceso.

- Postgres 16 + PostGIS 3.4 corriendo en Docker en una Raspberry Pi 5
  (arch `linux/arm64/v8`), imagen `imresamu/postgis:16-3.4` (el `postgis/postgis`
  oficial solo publica `amd64`, no sirve en la Pi).
- Contenedor: `postgis`. Volumen de datos en
  `/mnt/immich-data/postgis/data` (comparte disco de 4TB con Immich, pero es
  una instancia y base de datos independientes, no son los mismos datos).
- Base de datos: `incendios_db`. Usuario: `kraken`, password `postgis_2026`.
- El usuario se conecta a la Pi por SSH; Claude no tiene acceso directo, así
  que los comandos para ejecutar allí se entregan como texto para que el
  usuario los corra y pegue el resultado.
- La migración de la Pi a Supabase se hizo con
  [`scripts/copy_to_supabase.py`](../scripts/copy_to_supabase.py) (copia
  fila a fila vía `ST_AsEWKB`/`ST_GeomFromEWKB`, sin reproyectar porque
  ambas bases ya estaban en SRID 4326), envuelto en
  [`scripts/migrate_to_supabase.sh`](../scripts/migrate_to_supabase.sh).

## Esquema

Tabla `incendios`: una fila por perímetro de incendio, `geom` en SRID 4326.
Definición completa en [`supabase/schema.sql`](../supabase/schema.sql).
Ver [data.md](data.md) para el detalle de qué contiene cada columna.

## Índices

- GIST sobre `geom` y sobre `geom_simplified`, btree sobre `iso2` e
  `initialdate`. Con ~30k filas totales no hace falta TimescaleDB — es una
  herramienta pensada para series temporales de alto volumen/ingesta
  continua, innecesaria aquí.
- **Lección aprendida (2026-07-17):** el índice no es lo que causaba el
  timeout al consultar España — el volumen de filas es pequeño. Reducir a 5
  decimales tampoco fue suficiente por sí solo cuando además se pedía
  Portugal a la vez. El cuello de botella real es la **CPU** de serializar
  miles de polígonos con muchos vértices en cada petición, no el tamaño de
  la respuesta ni el plan de consulta.

## Columna `geom_simplified` (2026-07-18)

Para evitar pagar el coste de `ST_Simplify` en cada request, se añadió una
columna `geom_simplified` (tolerancia `ST_SimplifyPreserveTopology(geom,
0.001)`, ~100m — de sobra para ver la forma del incendio a escala de país)
calculada **una sola vez** vía trigger `BEFORE INSERT OR UPDATE OF geom`
(función `set_geom_simplified()`). `get_fires` usa `geom_simplified` en vez
de `geom`. Cualquier carga futura con `scripts/load_supabase.sh` genera esta
columna automáticamente al insertar, sin pasos manuales — el trigger se
encarga. Ver
[`supabase/update_2026-07-18_simplify_geom.sql`](../supabase/update_2026-07-18_simplify_geom.sql)
para el backfill de las filas ya cargadas antes de este cambio.

Como aun así ES+PT combinados rozaban el límite, se subió también el
`statement_timeout` del rol `anon` a 20s (por defecto ronda los 8s) — ver
[`supabase/update_2026-07-18c_statement_timeout.sql`](../supabase/update_2026-07-18c_statement_timeout.sql).
Esto es un ajuste moderado, no una solución mágica: si una consulta de
verdad tardara más que eso, el problema seguiría siendo de fondo.

Aparte del rendimiento, hay un problema distinto de **latencia esporádica**:
el tier gratuito de Supabase hace un "cold start" tras un rato de
inactividad, y la primera petición después de eso puede tardar de más y dar
timeout aunque la consulta en sí sea rápida. Esto se mitiga en el frontend
con reintentos automáticos (`rpcWithRetry`, ver [frontend.md](frontend.md)),
no con más ajustes en la base de datos.

## Carga de datos nuevos (canal oficial: Supabase)

```bash
./scripts/load_supabase.sh
```

- Recorre **todos** los `.json` en la raíz del proyecto — no depende del
  nombre de fichero. `load_incendios.py` valida el *contenido* antes de
  intentar cargarlo (`looks_like_effis_geojson`): comprueba que sea una
  `FeatureCollection` en CRS EPSG:3035, con features `MultiPolygon` y las
  propiedades mínimas esperadas (`id`, `initialdate`, `finaldate`, `iso2`,
  `country`). Si un fichero no encaja, se omite con un aviso en vez de
  abortar toda la carga.
- Internamente sigue usando `load_incendios.py`:
  - Reconstruye la geometría manualmente a WKT, sin `shapely` ni GDAL.
  - Reproyecta en la propia consulta SQL con
    `ST_Transform(ST_SetSRID(ST_GeomFromText(...), 3035), 4326)`.
  - Cuidado con los campos de fecha: `initialdate`/`finaldate` a veces
    incluyen fracción de segundos (`.317`) — se detecta antes de aplicar el
    formato correcto a `strptime`.
  - Usa `ON CONFLICT (id) DO NOTHING`, así que cargar el mismo fichero dos
    veces (o ficheros con rangos de fechas solapados) no duplica filas.
- `load_incendios.py` se puede seguir usando suelto contra cualquier host
  (por ejemplo, para volver a cargar en la Pi si hiciera falta):
  ```bash
  ./.venv/bin/python load_incendios.py <fichero>.json --host <host> --user <user> --password <pass>
  ```

## Tabla derivada `fire_zones` (2026-07-18)

Agrupa incendios de `incendios` cuyas geometrías se solapan o se tocan **a
lo largo de todos los años**, en "zonas" — para responder a "¿cuánta
superficie ha ardido en total en este mismo sitio a lo largo del tiempo?".

- Columnas: `id` (identificador), `iso2` (país; una zona no cruza fronteras,
  se agrupa por país por separado), `geom` (unión de las geometrías
  simplificadas que forman la zona), `history` (jsonb: array con un objeto
  por incendio que contribuyó a la zona — `fire_id`, `date`, `year`,
  `area_ha`).
- Agrupación con `ST_ClusterDBSCAN(geom_simplified, eps := 0, minpoints := 1)
  OVER (PARTITION BY iso2)`: con `eps=0` solo junta geometrías que
  **realmente se solapan o tocan** (no por cercanía), y lo hace de forma
  transitiva (si A solapa con B y B con C, los tres acaban en la misma zona
  aunque A y C no se toquen directamente). Se usó esta función porque, a
  diferencia de `ST_ClusterIntersecting` (agregada, devuelve un array de
  clusters), `ST_ClusterDBSCAN` es una *window function*: da un id de grupo
  por fila, que es lo que hace falta para agrupar con `GROUP BY` y construir
  el `history` de cada zona.
- **Ojo con sumar área**: sumar `area_ha` de cada incendio dentro de una
  zona cuenta dos veces el suelo que ardió, por ejemplo, en 2015 y de nuevo
  en 2022 — es una métrica válida como "hectáreas-incendio acumuladas", pero
  no es la superficie física distinta que ha ardido alguna vez (para eso
  habría que usar `ST_Area(geom::geography)` sobre la geometría ya unida de
  la zona).
- **No se recalcula sola**: hay que llamar a `SELECT rebuild_fire_zones();`
  a mano tras cargar datos nuevos con `scripts/load_supabase.sh` — es una
  operación pesada sobre toda la tabla, no algo para disparar por trigger en
  cada insert. Ver
  [`supabase/update_2026-07-18_fire_zones.sql`](../supabase/update_2026-07-18_fire_zones.sql).
- Columnas resumen precalculadas (`num_fires`, `total_area_ha`,
  `first_year`, `last_year`) — igual que con `geom_simplified`, se calculan
  una vez en `rebuild_fire_zones()` en vez de parsear el jsonb `history` en
  cada consulta. Ver
  [`supabase/update_2026-07-18b_fire_zones_rpc.sql`](../supabase/update_2026-07-18b_fire_zones_rpc.sql).
- Función RPC `get_fire_zones(country_codes text[])`: devuelve GeoJSON con
  esas columnas resumen (no el `history` completo, para no engordar la
  respuesta). Consumida desde el frontend en la capa "Zonas de
  reincidencia" — ver [frontend.md](frontend.md).
