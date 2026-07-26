-- Ejecutar en el SQL Editor de Supabase (después de
-- update_2026-07-26b_solar_plants_rpc.sql, que ya creaste).
--
-- get_solar_plants() pasa a aceptar un filtro opcional: solo plantas cuyo
-- centro cae dentro de una zona quemada (fire_zones, que ya es la unión de
-- todo el histórico de incendios en ese sitio) o a menos de radius_m metros
-- de su borde. Se usa un radio y no solo ST_Contains porque el centro de la
-- planta no es el límite exacto de la instalación real.
--
-- DROP explícito porque cambia la firma (antes sin argumentos): si no se
-- borra, Postgres deja las dos versiones y una llamada sin argumentos
-- queda ambigua entre "la de 0 argumentos" y "la de 2 con defaults".
DROP FUNCTION IF EXISTS get_solar_plants();

CREATE OR REPLACE FUNCTION get_solar_plants(
  near_fires_only boolean DEFAULT false,
  radius_m numeric DEFAULT 200
)
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
      'geometry', ST_AsGeoJSON(sp.geom, 5)::json,
      'properties', json_build_object(
        'name', sp.name,
        'operator', sp.operator,
        'plant_method', sp.plant_method,
        'output_electricity', sp.output_electricity,
        'start_date_raw', sp.start_date_raw,
        'start_year', sp.start_year
      )
    ) AS feature
    FROM solar_plants sp
    WHERE NOT near_fires_only OR EXISTS (
      SELECT 1 FROM fire_zones fz
      WHERE ST_DWithin(sp.geom::geography, fz.geom::geography, radius_m)
    )
  ) f
$$;

GRANT EXECUTE ON FUNCTION get_solar_plants(boolean, numeric) TO anon;
