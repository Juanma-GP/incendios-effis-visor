-- Ejecutar en el SQL Editor de Supabase (después de
-- update_2026-07-18_fire_zones.sql, que ya creaste).
--
-- Añade columnas resumen precalculadas a fire_zones (nº de incendios, área
-- total, primer/último año) para no tener que parsear el jsonb `history` en
-- cada consulta desde el frontend — misma lección que con geom_simplified:
-- calcular una vez al reconstruir, no en cada request.

ALTER TABLE fire_zones ADD COLUMN IF NOT EXISTS num_fires int NOT NULL DEFAULT 0;
ALTER TABLE fire_zones ADD COLUMN IF NOT EXISTS total_area_ha numeric NOT NULL DEFAULT 0;
ALTER TABLE fire_zones ADD COLUMN IF NOT EXISTS first_year int;
ALTER TABLE fire_zones ADD COLUMN IF NOT EXISTS last_year int;

CREATE OR REPLACE FUNCTION rebuild_fire_zones() RETURNS void AS $$
BEGIN
  TRUNCATE fire_zones;

  INSERT INTO fire_zones (iso2, geom, history, num_fires, total_area_ha, first_year, last_year)
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
    ),
    count(*),
    sum(area_ha),
    min(EXTRACT(YEAR FROM initialdate)::int),
    max(EXTRACT(YEAR FROM initialdate)::int)
  FROM (
    SELECT
      id, iso2, initialdate, area_ha, geom_simplified,
      ST_ClusterDBSCAN(geom_simplified, eps := 0, minpoints := 1) OVER (PARTITION BY iso2) AS cluster_id
    FROM incendios
  ) clustered
  GROUP BY iso2, cluster_id;
END;
$$ LANGUAGE plpgsql;

-- Recalcula ya con las columnas nuevas (vuelve a agrupar todo, es la misma
-- operación pesada de antes).
SELECT rebuild_fire_zones();

-- Función RPC: GeoJSON con las columnas resumen (no el history completo,
-- para no engordar la respuesta — si hiciera falta el detalle por incendio
-- se puede añadir después una función get_fire_zone_history(zone_id)).
CREATE OR REPLACE FUNCTION get_fire_zones(country_codes text[] DEFAULT NULL)
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
      'geometry', ST_AsGeoJSON(geom, 5)::json,
      'properties', json_build_object(
        'id', id,
        'iso2', iso2,
        'num_fires', num_fires,
        'total_area_ha', total_area_ha,
        'first_year', first_year,
        'last_year', last_year
      )
    ) AS feature
    FROM fire_zones
    WHERE country_codes IS NULL OR iso2 = ANY(country_codes)
  ) f
$$;

GRANT EXECUTE ON FUNCTION get_fire_zones TO anon;
