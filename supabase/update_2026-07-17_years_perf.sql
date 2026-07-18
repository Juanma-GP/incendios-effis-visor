-- Ejecutar en el SQL Editor de Supabase (proyecto ya creado con schema.sql).
--
-- Motivo: la consulta de España daba timeout (get_fires serializaba miles
-- de geometrías con precisión completa en una sola respuesta), y no había
-- forma de saber qué años existen sin haber descargado ya todas las
-- geometrías. Esto añade índices, reduce el peso de la respuesta, permite
-- pedir varios años a la vez, y separa "qué años hay" de "traer las
-- geometrías" en dos funciones distintas.

-- Índices para acelerar el filtrado por país/año (antes solo existía el GIST de geom)
CREATE INDEX IF NOT EXISTS incendios_iso2_idx ON incendios (iso2);
CREATE INDEX IF NOT EXISTS incendios_initialdate_idx ON incendios (initialdate);

-- get_fires ahora acepta varios años (filter_years int[]) en vez de uno solo,
-- y reduce la precisión de las coordenadas a 5 decimales (~1m, de sobra para
-- este visor) para que la respuesta pese mucho menos.
DROP FUNCTION IF EXISTS get_fires(text[], int);

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
      'geometry', ST_AsGeoJSON(geom, 5)::json,
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

-- Función ligera (sin geometría): solo los años disponibles para los países
-- dados. Se usa para poblar el selector de años sin descargar geometrías.
CREATE OR REPLACE FUNCTION get_years(country_codes text[] DEFAULT NULL)
RETURNS int[]
LANGUAGE sql
STABLE
AS $$
  SELECT ARRAY(
    SELECT DISTINCT EXTRACT(YEAR FROM initialdate)::int
    FROM incendios
    WHERE country_codes IS NULL OR iso2 = ANY(country_codes)
    ORDER BY 1
  );
$$;

GRANT EXECUTE ON FUNCTION get_years TO anon;
