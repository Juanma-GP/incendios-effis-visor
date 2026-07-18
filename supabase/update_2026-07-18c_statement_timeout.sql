-- Ejecutar en el SQL Editor de Supabase.
--
-- Sube el statement_timeout para las peticiones vía API (rol `anon`), por
-- si ES+PT combinados siguen rozando el límite por defecto (~8s) aunque ya
-- se optimizó la consulta (geom_simplified, 5 decimales, índices).
-- Ajuste moderado, no una solución mágica: si la consulta de verdad tarda
-- más de esto, el problema sigue siendo de fondo, no el timeout en sí.

ALTER ROLE anon SET statement_timeout = '20s';
ALTER ROLE authenticated SET statement_timeout = '20s';

-- PostgREST cachea la config de roles; esto le pide recargarla sin reiniciar.
NOTIFY pgrst, 'reload config';
