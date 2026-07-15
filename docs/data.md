# Origen de los datos

- Fuente: EFFIS/WILDFIRE Database (Unión Europea, Copernicus).
- Formato original: GeoJSON, CRS EPSG:3035 (ETRS89-LAEA Europe).
- Países incluidos: ES, PT, MA, FR. El foco del visor es ES/PT, pero el resto
  está disponible como opción.
- Se han descargado dos extracciones que juntas cubren 2010-05-01 a
  2026-07-15 (hay solape en torno a mayo de 2022, resuelto en la carga con
  `ON CONFLICT (id) DO NOTHING`):
  - `9ec9627f90ff4d60887341fde3bce389.json` — 2022-05-01 a 2026-07-15.
  - `dc6cf710210442948df37fb31e0e0c8f.json` — 2010-05-01 a 2022-05-01.
  - Cada `.json` trae su `.readme.txt` con metadatos/licencia EFFIS.
- **Limitación conocida del dataset** (documentada en el `readme.txt` de
  EFFIS): el producto MODIS Rapid Damage Assessment solo mapea incendios de
  ~30 hectáreas o más (resolución de satélite 250m). Representa
  aproximadamente el 75-80% del área total quemada en la UE — los incendios
  pequeños no están y nunca lo van a estar en este dataset. No es un fallo de
  carga ni del visor.
- Esquema de `properties` en el GeoJSON (una feature por incendio):
  `id`, `initialdate`, `finaldate` (formato `YYYY/MM/DD HH:MM:SS`, a veces
  con fracción de segundos, `finaldate` siempre con sufijo `+00`),
  `area_ha`, `iso2`, `iso3`, `country`, `admlvl1`/`admlvl2`/`admlvl3`/`admlvl5`
  (jerarquía administrativa región/comunidad/provincia/municipio — no existe
  `admlvl4` en el dataset, cada columna representa siempre el mismo nivel
  posicional en todos los países), `map_source` (`sentinel2` o `modis`
  según la extracción), y varios `*_percent` de cobertura de terreno
  (bosque, agricultura, etc. — pueden venir `null`).
