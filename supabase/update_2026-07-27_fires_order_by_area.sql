-- Ejecutar en el SQL Editor de Supabase.
--
-- get_fires() devolvía las features sin orden garantizado. En el frontend,
-- MapLibre pinta una capa "fill" en el orden en que llegan las features de
-- la fuente GeoJSON: si un incendio grande sale antes que uno pequeño que
-- está dentro o solapado, el pequeño queda tapado. Se ordena por area_ha
-- DESCENDENTE dentro de json_agg, así los incendios grandes se pintan
-- primero (quedan "debajo") y los pequeños se pintan después (quedan
-- "encima", visibles).

CREATE OR REPLACE FUNCTION get_fires(country_codes text[] DEFAULT NULL, filter_years int[] DEFAULT NULL)
RETURNS json
LANGUAGE sql
STABLE
AS $$
  SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(json_agg(feature ORDER BY area_ha DESC), '[]'::json)
  )
  FROM (
    SELECT
      area_ha,
      json_build_object(
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
