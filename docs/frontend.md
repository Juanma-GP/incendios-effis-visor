# Frontend

`frontend/index.html`, página única sin build step: MapLibre GL JS +
`supabase-js` vía CDN, llamando directamente a la función RPC `get_fires` de
Supabase (ver [database.md](database.md)) — sin backend propio. El
[backend FastAPI](backend.md) queda como legacy/histórico, ya no lo usa el
frontend.

`SUPABASE_URL` y `SUPABASE_KEY` (la `publishable key`, equivalente pública a
la antigua `anon key`) están hardcodeadas en el HTML — es seguro porque son
públicas por diseño y la tabla tiene RLS con política de solo lectura.

Todas las llamadas RPC pasan por `rpcWithRetry(fn, params)` (2 reintentos,
1.5s de espera entre cada uno) en vez de llamar a `supabaseClient.rpc`
directo — la primera consulta tras un rato de inactividad puede tardar de
más (cold start del proyecto/pooler en el tier gratuito de Supabase) y dar
timeout aunque los reintentos siguientes vayan bien; con esto no hace falta
que el usuario recargue la página a mano.

## Mapa base

CartoDB Voyager (raster, sin API key) — muestra fronteras administrativas
(comunidades autónomas, comarcas) y topónimos con buen detalle. Alternativa
más minimalista: cambiar la URL de `rastertiles/voyager` a `light_all`
(Positron).

## Controles

- **Países**: combobox multi-selección (`<select multiple>`), ES/PT
  preseleccionados, FR/MA disponibles. Cambiar la selección dispara
  automáticamente `get_years` (barata, sin geometría) para repoblar el rango
  de años — pero no descarga geometrías todavía.
- **Años**: slider de rango de dos manecillas **propio** (dos `<div>`
  arrastrables con `pointerdown`/`pointermove`/`pointerup`, no dos
  `<input type="range">` superpuestos). Se descartó la técnica de dos
  inputs nativos superpuestos porque cuando ambas manecillas caen en el
  mismo valor (el caso por defecto: las dos en el último año), arrastrar
  una movía las dos a la vez — un problema conocido de ese truco con CSS.
  Con manecillas propias cada una se arrastra de forma independiente
  siempre (`draggingHandle` guarda cuál se está moviendo), y hacer click en
  el carril mueve la manecilla más cercana al punto pulsado.
  `selectedYears()` genera todos los años enteros entre las dos manecillas
  (rango continuo, no lista de años sueltos). Por defecto ambas manecillas
  se colocan en el **último año** disponible (rango de un solo año), para no
  disparar por defecto una consulta pesada de todo el histórico. El botón
  "Consultar" es el único que dispara la descarga de geometrías
  (`get_fires`) para la combinación de países × rango de años seleccionada.
  La consulta de años (`get_years`) sí se dispara sola, tanto al cargar la
  página como al cambiar los países — es barata porque no trae geometría.

## Color por año

**El color se basa en el rango de años realmente SELECCIONADO (`selectedYears()`
del slider), no en todo el histórico disponible** — esto cambió el
2026-07-18 tras detectar que colorear sobre el rango completo (2010-2026)
hacía que seleccionar solo 2-3 años cercanos diera colores casi idénticos
(ambos cerca del mismo extremo del degradado completo).

`colorsByRecency(years)` ordena los años seleccionados de más reciente a
más antiguo y ancla siempre **rojo al año más reciente**, extendiéndose
hacia atrás con marrón, amarillo y verde según cuántos años se hayan
elegido:

- 1 año → rojo
- 2 años → rojo, marrón
- 3 años → rojo, marrón, amarillo
- 4 años → rojo, marrón, amarillo, verde
- 5+ años → se interpola de forma continua entre rojo y verde
  (`colorAtRankFraction`), en vez de solo 4 colores discretos.

La opacidad sigue la misma lógica de recencia: 1.0 el año más reciente,
bajando hasta 0.15 el más antiguo del rango seleccionado.
`updateYearPaint(years)` construye expresiones `match` de MapLibre (una
entrada por año exacto) en vez de `interpolate`, ya que ahora el color no es
una función continua del año en sí, sino del *rango* dentro de la selección
actual.

## Caché client-side por país y año

`dataCache` guarda en memoria las features ya descargadas, indexadas por
clave `"iso2:año"` (ej. `"ES:2023"`). Al pulsar "Consultar":

1. Para cada país seleccionado, se calculan los años seleccionados que
   **no** están ya en caché para ese país.
2. Solo esas combinaciones país+años que faltan se piden con
   `supabase.rpc("get_fires", { country_codes: [code], filter_years: [...] })`
   (una llamada por país, con todos sus años pendientes de golpe).
3. El resultado se reparte en `dataCache` por año (usando la propiedad
   `year` de cada feature) y se combina en cliente con lo que ya había en
   caché para formar la `FeatureCollection` final que se asigna como `data`
   de la fuente GeoJSON del mapa.

Así, si ya tienes ES 2023 cargado y seleccionas también 2022, solo se pide
ES 2022 — no se repite 2023. La caché es independiente de qué esté
seleccionado en cada momento en el combobox de años (se puede quitar y
volver a poner un año sin red, si ya se descargó antes).

## Capa de zonas de reincidencia (2026-07-18)

Checkbox "Zonas de reincidencia" en el panel — es un **modo exclusivo**, no
una capa adicional: al marcarlo, se oculta toda la sección de años
(`#years-section`, vía `updateZonesToggleUI()`) y "Consultar" pasa a mostrar
**solo** `zones-fill`/`zones-outline`, ocultando `fires-fill`/`fires-outline`
(y viceversa al desmarcarlo). Tiene sentido porque una zona agrupa
incendios de todo el histórico — filtrar por año no aplicaría a esa vista.

- `zonesCache`: caché client-side por país (no por año, a diferencia de
  `dataCache`), mismo patrón de "solo pedir lo que falta".
- Capa coloreada por `num_fires` (nº de incendios que se solaparon en esa
  zona) con una escala de **tramos fijos** (`step`, no `interpolate`):
  1 → `#f3e8ff`, 2 → `#c4b5fd`, 3 → `#a78bfa`, 4 → `#7c3aed`, 5+ →
  `#4c1d95`. Se probó primero una escala continua entre el mínimo y máximo
  de cada consulta, pero como la mayoría de zonas tienen 1 solo incendio
  (sin reincidencia) y muy pocas tienen muchos, esa escala dejaba casi todo
  en el mismo tono claro y solo un par de zonas extremas en el oscuro — con
  tramos fijos cada nivel de reincidencia se distingue, y la escala es
  consistente entre consultas (no cambia según lo que esté cargado).
  Deliberadamente un morado, distinto a la paleta rojo/verde de los
  incendios individuales.
- Ninguna de las dos capas se destruye al cambiar de modo, solo se oculta
  (`visibility: none`) — volver a un modo ya cargado no vuelve a pedir nada
  a Supabase si los países no cambiaron.
- Popup al click: nº de incendios, área acumulada (ojo, ver el aviso sobre
  doble conteo en [database.md](database.md)), y rango de años
  (`first_year`-`last_year`).

## Panel de controles

El panel (`#panel`) está en alpha 0.04 (casi invisible) por defecto, para no
tapar el mapa, y sube a 0.95 al pasar el ratón por encima (`transition` de
`background-color`, con `#panel:hover`).

## Cómo servirlo en local

```bash
cd frontend && python3 -m http.server 8080
# abrir http://localhost:8080
```
