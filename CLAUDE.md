# Incendios — visor de áreas quemadas (EFFIS)

## Objetivo del proyecto

Visualizar en un mapa web las áreas quemadas año tras año en España y Portugal
(el dataset también incluye Francia y Marruecos, pero el foco del visor es
ES/PT), con un color por año en gradiente que se pueda superponer para ver la
acumulación de superficie arrasada a lo largo del tiempo.

## Documentación detallada

- [docs/data.md](docs/data.md) — origen, ficheros, esquema de propiedades y
  limitaciones conocidas del dataset EFFIS.
- [docs/database.md](docs/database.md) — Postgres+PostGIS en la Raspberry
  Pi, esquema de la tabla, índices, script de carga, plan de migración a
  Supabase.
- [docs/backend.md](docs/backend.md) — API FastAPI (endpoints, config).
- [docs/frontend.md](docs/frontend.md) — mapa MapLibre, controles, lógica de
  color por año, caché client-side por país.

## Roadmap

1. ~~Levantar Postgres+PostGIS en la Pi~~ ✅
2. ~~Crear tabla `incendios` y cargar el GeoJSON (2010-2026)~~ ✅
3. ~~Backend FastAPI sirviendo GeoJSON filtrado por país/año~~ ✅
4. ~~Frontend MapLibre con gradiente de color por año, filtros de país/año,
   caché client-side~~ ✅
5. **En evaluación:** desplegar el frontend en GitHub Pages (estático) y
   migrar los datos a Supabase, sustituyendo el backend FastAPI por
   PostgREST + una función SQL que devuelva GeoJSON directamente al
   frontend. Ver detalles y trade-offs en
   [docs/database.md](docs/database.md#plan-futuro-migración-a-supabase).
6. (Futuro, no decidido aún) posibles mejoras: agregados por
   comunidad/provincia, estadísticas de superficie quemada por año/región.

## Convenciones de trabajo con el usuario

- El usuario se conecta a la Raspberry Pi por SSH; Claude no tiene acceso
  directo a la Pi, así que los comandos para ejecutar allí se entregan como
  texto para que el usuario los corra y pegue el resultado.
- Preferencia: scripts sencillos y explícitos antes que frameworks/tooling
  pesado (ver decisión de no usar TimescaleDB, ni `shapely`/GDAL para la
  carga, en [docs/database.md](docs/database.md)).
