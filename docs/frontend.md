# Frontend

`frontend/index.html`, página única sin build step: MapLibre GL JS vía CDN,
consumiendo el [backend](backend.md) (`API_BASE = "http://localhost:8000"`,
ajustar si se despliega en otro sitio).

## Mapa base

CartoDB Voyager (raster, sin API key) — muestra fronteras administrativas
(comunidades autónomas, comarcas) y topónimos con buen detalle. Alternativa
más minimalista: cambiar la URL de `rastertiles/voyager` a `light_all`
(Positron).

## Controles

- **Países**: combobox multi-selección (`<select multiple>`), ES/PT
  preseleccionados, FR/MA disponibles. Marcar/desmarcar no dispara ninguna
  petición por sí solo — solo el botón "Consultar" llama a la API.
- **Años**: combobox multi-selección poblado dinámicamente tras la consulta,
  actúa como filtro client-side (`map.setFilter`, sin red) sobre los datos ya
  cargados.

## Color por año

Gradiente continuo de 4 paradas (verde → amarillo → marrón → rojo),
repartidas uniformemente entre el año mínimo y máximo de los datos cargados,
vía expresión `interpolate` de MapLibre sobre la propiedad `year` de cada
feature. La opacidad también interpola, de 0.15 (año más antiguo) a 1.0 (año
más reciente). Se decidió gradiente en vez de paleta categórica porque con
~16 años distintos una paleta categórica se vuelve difícil de distinguir a
simple vista; el gradiente comunica intuitivamente antigüedad/recencia.

## Caché client-side por país

`countryCache` guarda en memoria las features ya descargadas, indexadas por
código `iso2`. Al pulsar "Consultar":

1. Se calculan los países seleccionados que **no** están ya en caché.
2. Solo esos se piden a `/api/fires?iso2=...`.
3. El resultado final combina en cliente la caché de todos los países
   seleccionados (los ya cargados + los recién descargados) y se asigna como
   `data` de la fuente GeoJSON del mapa.

Así, si ya tienes ES+PT cargados y añades FR, solo se descarga FR — no se
vuelve a pedir ES+PT a la base de datos.

## Cómo servirlo en local

```bash
cd frontend && python3 -m http.server 8080
# abrir http://localhost:8080
```
