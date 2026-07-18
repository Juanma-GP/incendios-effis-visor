-- Ejecutar en el SQL Editor de Supabase.
--
-- Motivo: reducir la precisión decimal (ver update_2026-07-17) no bastó —
-- ES+PT juntos siguen dando timeout. El coste real no es el peso de la
-- respuesta, es la CPU de serializar miles de polígonos con muchos
-- vértices en cada consulta. La solución: precalcular UNA VEZ una versión
-- simplificada de cada geometría (menos vértices, visualmente equivalente
-- a la escala de un visor nacional) y usar esa columna en vez de `geom`
-- en la función get_fires. Así el trabajo pesado (ST_Simplify) se paga una
-- sola vez al cargar datos, no en cada petición.

ALTER TABLE incendios ADD COLUMN IF NOT EXISTS geom_simplified geometry(MultiPolygon, 4326);

-- Backfill de las filas ya cargadas (tolerancia ~0.001 grados, ~100m — de
-- sobra para ver la forma del incendio a escala de país).
UPDATE incendios
SET geom_simplified = ST_Multi(ST_SimplifyPreserveTopology(geom, 0.001))
WHERE geom_simplified IS NULL;

CREATE INDEX IF NOT EXISTS incendios_geom_simplified_idx ON incendios USING GIST (geom_simplified);

-- Trigger para que las cargas futuras (load_supabase.sh) calculen
-- geom_simplified automáticamente, sin volver a correr este UPDATE a mano.
CREATE OR REPLACE FUNCTION set_geom_simplified() RETURNS trigger AS $$
BEGIN
  NEW.geom_simplified := ST_Multi(ST_SimplifyPreserveTopology(NEW.geom, 0.001));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS incendios_set_geom_simplified ON incendios;
CREATE TRIGGER incendios_set_geom_simplified
BEFORE INSERT OR UPDATE OF geom ON incendios
FOR EACH ROW EXECUTE FUNCTION set_geom_simplified();

CREATE OR REPLACE FUNCTION get_fires(country_codes text[] DEFAULT NULL, filter_years int[] DEFAULT NULL)
RETURNS json
LANGUAGE sql
STABLE
AS $$
  SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(json_agg(feature), '[]'::json)
  )
  FROM (
    SELECT json_build_object(
      'type', 'Feature',
      'geometry', ST_AsGeoJSON(geom_simplified, 5)::json,
      'properties', json_build_object(
        'id', id,
        'year', EXTRACT(YEAR FROM initialdate)::int,
        'iso2', iso2,
        'country', country,
        'admlvl1', admlvl1,
        'admlvl2', admlvl2,
        'admlvl3', admlvl3,
        'area_ha', area_ha,
        'initialdate', initialdate,
        'finaldate', finaldate
      )
    ) AS feature
    FROM incendios
    WHERE (country_codes IS NULL OR iso2 = ANY(country_codes))
      AND (filter_years IS NULL OR EXTRACT(YEAR FROM initialdate)::int = ANY(filter_years))
  ) f
$$;

GRANT EXECUTE ON FUNCTION get_fires TO anon;
