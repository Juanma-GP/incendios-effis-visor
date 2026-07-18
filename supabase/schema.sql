-- Ejecutar completo en el SQL Editor de Supabase.

CREATE TABLE incendios (
    id                                  integer PRIMARY KEY,
    initialdate                        timestamp,
    finaldate                          timestamp,
    area_ha                            numeric,
    iso2                               text,
    iso3                               text,
    country                            text,
    admlvl1                            text,
    admlvl2                            text,
    admlvl3                            text,
    admlvl5                            text,
    map_source                         text,
    broadleaved_forest_percent         numeric,
    coniferous_forest_percent          numeric,
    mixed_forest_percent               numeric,
    sclerophillous_vegetation_percent  numeric,
    transitional_vegetation_percent    numeric,
    other_natural_percent              numeric,
    agriculture_percent                numeric,
    artificial_percent                 numeric,
    other_percent                      numeric,
    natura2k_percent                   numeric,
    geom                               geometry(MultiPolygon, 4326),
    -- Versión simplificada de geom (menos vértices), calculada
    -- automáticamente por trigger. Se usa en get_fires para no pagar el
    -- coste de simplificar en cada consulta — el problema no es el peso de
    -- la respuesta, es la CPU de serializar geometrías muy detalladas para
    -- miles de filas (España daba timeout con la geometría completa).
    geom_simplified                    geometry(MultiPolygon, 4326)
);

CREATE INDEX incendios_geom_idx ON incendios USING GIST (geom);
CREATE INDEX incendios_geom_simplified_idx ON incendios USING GIST (geom_simplified);
CREATE INDEX incendios_iso2_idx ON incendios (iso2);
CREATE INDEX incendios_initialdate_idx ON incendios (initialdate);

CREATE OR REPLACE FUNCTION set_geom_simplified() RETURNS trigger AS $$
BEGIN
  -- Tolerancia ~0.001 grados (~100m): de sobra para ver la forma del
  -- incendio a escala de país en el visor.
  NEW.geom_simplified := ST_Multi(ST_SimplifyPreserveTopology(NEW.geom, 0.001));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER incendios_set_geom_simplified
BEFORE INSERT OR UPDATE OF geom ON incendios
FOR EACH ROW EXECUTE FUNCTION set_geom_simplified();

-- Seguridad: RLS activado, solo lectura pública, nada de escritura
ALTER TABLE incendios ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON incendios TO anon;
CREATE POLICY "Lectura publica" ON incendios FOR SELECT TO anon USING (true);

-- Función RPC que devuelve GeoJSON, para llamar directo desde el frontend.
-- Coordenadas a 5 decimales (~1m, de sobra para este visor) para que la
-- respuesta no pese de más con países grandes (España).
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

-- Tabla derivada: agrupa incendios cuyas geometrías se solapan o se tocan
-- (a lo largo de todos los años) en "zonas", para ver cuánta superficie ha
-- ardido en total en un mismo sitio a lo largo del tiempo.
CREATE TABLE fire_zones (
    id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso2          text NOT NULL,
    geom          geometry(MultiPolygon, 4326) NOT NULL,
    history       jsonb NOT NULL,
    -- Resumen precalculado (evita parsear el jsonb en cada consulta):
    num_fires     int NOT NULL DEFAULT 0,
    total_area_ha numeric NOT NULL DEFAULT 0,
    first_year    int,
    last_year     int
);

CREATE INDEX fire_zones_geom_idx ON fire_zones USING GIST (geom);
CREATE INDEX fire_zones_iso2_idx ON fire_zones (iso2);

ALTER TABLE fire_zones ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON fire_zones TO anon;
CREATE POLICY "Lectura publica" ON fire_zones FOR SELECT TO anon USING (true);

-- Recalcula fire_zones desde cero a partir de incendios. Agrupación por
-- ST_ClusterDBSCAN(geom, eps := 0, minpoints := 1): con eps=0 solo junta
-- geometrías que realmente se solapan/tocan (no por cercanía), de forma
-- transitiva. Hay que volver a llamarla tras cargar datos nuevos.
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

SELECT rebuild_fire_zones();

-- Función RPC: GeoJSON con las columnas resumen (no el history completo,
-- para no engordar la respuesta).
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
