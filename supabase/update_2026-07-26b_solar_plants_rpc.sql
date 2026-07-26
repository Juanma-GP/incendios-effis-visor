-- Ejecutar en el SQL Editor de Supabase (después de
-- update_2026-07-26_solar_plants.sql, que ya creaste).
--
-- Función RPC de solo lectura para la capa "Plantas solares" del frontend.
-- Sin filtro por país (solar_plants no tiene iso2 — viene de un bbox fijo
-- ES/PT, ver scripts/load_osm_solar.py), y con pocos puntos (~4.500) no
-- hace falta paginar ni simplificar geometría.

CREATE OR REPLACE FUNCTION get_solar_plants()
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
        'name', name,
        'operator', operator,
        'plant_method', plant_method,
        'output_electricity', output_electricity,
        'start_date_raw', start_date_raw,
        'start_year', start_year
      )
    ) AS feature
    FROM solar_plants
  ) f
$$;

GRANT EXECUTE ON FUNCTION get_solar_plants TO anon;
