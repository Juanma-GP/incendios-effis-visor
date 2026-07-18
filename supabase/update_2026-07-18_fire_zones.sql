-- Ejecutar en el SQL Editor de Supabase.
--
-- Nueva tabla derivada: agrupa incendios cuyas geometrías se solapan o se
-- tocan (a lo largo de todos los años) en "zonas", para ver cuánta
-- superficie ha ardido en total en un mismo sitio a lo largo del tiempo.
--
-- Agrupación por ST_ClusterDBSCAN(geom, eps := 0, minpoints := 1): con
-- eps=0 solo junta geometrías que realmente se solapan/tocan (no por
-- cercanía), y lo hace de forma transitiva (si A solapa con B y B con C,
-- los tres acaban en la misma zona aunque A y C no se toquen). Es una
-- window function: da un id de grupo por fila, a diferencia de
-- ST_ClusterIntersecting (que es agregada y no sirve para esto).

CREATE TABLE IF NOT EXISTS fire_zones (
    id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso2    text NOT NULL,
    geom    geometry(MultiPolygon, 4326) NOT NULL,
    history jsonb NOT NULL
);

CREATE INDEX IF NOT EXISTS fire_zones_geom_idx ON fire_zones USING GIST (geom);
CREATE INDEX IF NOT EXISTS fire_zones_iso2_idx ON fire_zones (iso2);

ALTER TABLE fire_zones ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON fire_zones TO anon;
DROP POLICY IF EXISTS "Lectura publica" ON fire_zones;
CREATE POLICY "Lectura publica" ON fire_zones FOR SELECT TO anon USING (true);

-- Recalcula fire_zones desde cero a partir de incendios. Hay que volver a
-- llamarla tras cargar datos nuevos (scripts/load_supabase.sh no lo hace
-- automáticamente, es una operación pesada sobre toda la tabla).
CREATE OR REPLACE FUNCTION rebuild_fire_zones() RETURNS void AS $$
BEGIN
  TRUNCATE fire_zones;

  INSERT INTO fire_zones (iso2, geom, history)
  SELECT
    iso2,
    ST_Multi(ST_Union(geom_simplified)),
    jsonb_agg(
      jsonb_build_object(
        'fire_id', id,
        'date', initialdate::date,
        'year', EXTRACT(YEAR FROM initialdate)::int,
        'area_ha', area_ha
      )
      ORDER BY initialdate
    )
  FROM (
    SELECT
      id, iso2, initialdate, area_ha, geom_simplified,
      ST_ClusterDBSCAN(geom_simplified, eps := 0, minpoints := 1) OVER (PARTITION BY iso2) AS cluster_id
    FROM incendios
  ) clustered
  GROUP BY iso2, cluster_id;
END;
$$ LANGUAGE plpgsql;

-- Primera carga:
SELECT rebuild_fire_zones();
