# Incendios — visor de áreas quemadas (EFFIS)

## Objetivo del proyecto

Visualizar en un mapa web las áreas quemadas año tras año en España y Portugal
(el dataset también incluye Francia y Marruecos, pero el foco del visor es
ES/PT), con un color por año en gradiente que se pueda superponer para ver la
acumulación de superficie arrasada a lo largo del tiempo.

## Documentación detallada

- [docs/data.md](docs/data.md) — origen, ficheros, esquema de propiedades y
  limitaciones conocidas del dataset EFFIS.
- [docs/database.md](docs/database.md) — Supabase (base de datos activa),
  esquema, índices, carga de datos nuevos, e histórico de la Raspberry Pi.
- [docs/backend.md](docs/backend.md) — API FastAPI (endpoints, config).
- [docs/frontend.md](docs/frontend.md) — mapa MapLibre, controles, lógica de
  color por año, caché client-side por país.

## Roadmap

1. ~~Levantar Postgres+PostGIS en la Pi~~ ✅
2. ~~Crear tabla `incendios` y cargar el GeoJSON (2010-2026)~~ ✅
3. ~~Backend FastAPI sirviendo GeoJSON filtrado por país/año~~ ✅
4. ~~Frontend MapLibre con gradiente de color por año, filtros de país/año,
   caché client-side~~ ✅
5. ~~Migrar los datos a Supabase (esquema, RLS, función RPC `get_fires`) y
   convertirlo en el canal oficial de nuevas cargas~~ ✅ — ver
   [docs/database.md](docs/database.md). La Pi queda como histórico.
6. ~~Adaptar el frontend para llamar a Supabase (`supabase-js` + RPC
   `get_fires`) en vez del backend FastAPI local~~ ✅ — el backend FastAPI
   queda como legacy, ver [docs/backend.md](docs/backend.md).
7. ~~Arreglar timeout al consultar países grandes (España): índices
   `iso2`/`initialdate`, coordenadas a 5 decimales, y función `get_years`
   separada (barata, sin geometría) para poblar el selector de años sin
   depender de la consulta pesada~~ ✅ — ver
   [docs/database.md](docs/database.md) y
   [`supabase/update_2026-07-17_years_perf.sql`](supabase/update_2026-07-17_years_perf.sql).
8. ~~Tabla derivada `fire_zones`: agrupa incendios que se solapan/tocan a lo
   largo de los años (vía `ST_ClusterDBSCAN`), con resumen precalculado
   (nº de incendios, área total, primer/último año) y función RPC
   `get_fire_zones`. Capa nueva en el visor ("Zonas de reincidencia"),
   coloreada por nº de reincidencias~~ ✅ — ver
   [docs/database.md](docs/database.md) y
   [docs/frontend.md](docs/frontend.md).
9. ~~Crear el repo remoto en GitHub, hacer push, y desplegar el frontend
   (ya 100% estático) en GitHub Pages~~ ✅ — repo público
   [Juanma-GP/incendios-effis-visor](https://github.com/Juanma-GP/incendios-effis-visor),
   visor en https://juanma-gp.github.io/incendios-effis-visor/, workflow
   [`.github/workflows/pages.yml`](.github/workflows/pages.yml). Ver
   [docs/frontend.md](docs/frontend.md#despliegue-en-github-pages-2026-07-18).
10. ~~Subir `statement_timeout` en Supabase y añadir reintentos en el
    frontend para el cold start del tier gratuito~~ ✅ — ver
    [docs/database.md](docs/database.md) y [docs/frontend.md](docs/frontend.md).
11. (Futuro, no decidido aún) posibles mejoras: agregados por
    comunidad/provincia, estadísticas de superficie quemada por año/región.

## Convenciones de trabajo con el usuario

- El usuario se conecta a la Raspberry Pi por SSH; Claude no tiene acceso
  directo a la Pi, así que los comandos para ejecutar allí se entregan como
  texto para que el usuario los corra y pegue el resultado.
- Preferencia: scripts sencillos y explícitos antes que frameworks/tooling
  pesado (ver decisión de no usar TimescaleDB, ni `shapely`/GDAL para la
  carga, en [docs/database.md](docs/database.md)).
