-- Ejecutar en el SQL Editor de Supabase.
--
-- Prototipo: plantas solares fotovoltaicas/termosolares desde
-- OpenStreetMap (power=plant + plant:source=solar), vía Overpass API. Solo
-- geometría de punto (centro de la instalación), no el polígono completo:
-- de las ~4.500 instalaciones en España/Portugal, la mitad son relaciones
-- OSM (multipolígonos con anillos internos/externos) cuya reconstrucción
-- exacta no aporta nada para el objetivo de este prototipo, que es solo
-- comprobar coincidencia espacial con zonas quemadas (ver CLAUDE.md,
-- roadmap punto 11).
--
-- start_date en OSM es un tag de texto libre, sin formato fijo ("2009",
-- "2009-03", "9/2009"...) y solo lo tiene ~13% de las instalaciones. Se
-- guarda tal cual en start_date_raw, y además el año extraído (si se puede)
-- en start_year, para poder filtrar/ordenar sin parsear en cada consulta.
-- Cargado por scripts/load_osm_solar.py.

CREATE TABLE IF NOT EXISTS solar_plants (
    osm_type            text NOT NULL,
    osm_id              bigint NOT NULL,
    name                text,
    operator            text,
    plant_method        text,
    output_electricity  text,
    start_date_raw      text,
    start_year          integer,
    geom                geometry(Point, 4326) NOT NULL,
    PRIMARY KEY (osm_type, osm_id)
);

CREATE INDEX IF NOT EXISTS solar_plants_geom_idx ON solar_plants USING GIST (geom);

ALTER TABLE solar_plants ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON solar_plants TO anon;
DROP POLICY IF EXISTS "Lectura publica" ON solar_plants;
CREATE POLICY "Lectura publica" ON solar_plants FOR SELECT TO anon USING (true);
