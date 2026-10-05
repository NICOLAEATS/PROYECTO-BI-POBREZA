-- Acceso SOLO LECTURA para compañeros (ejecutar como owner en Neon SQL Editor)
-- 1) Crear rol lector con password propia (cámbiala)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='equipo_bi_lector') THEN
    CREATE ROLE equipo_bi_lector WITH LOGIN PASSWORD 'CambiaEstaClave123*';
  END IF;
END $$;
-- 2) Permisos mínimos: conectar + usar schema + SELECT en tablas/vistas actuales y futuras
GRANT CONNECT ON DATABASE neondb TO equipo_bi_lector;
GRANT USAGE ON SCHEMA public TO equipo_bi_lector;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO equipo_bi_lector;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO equipo_bi_lector;
-- 3) Verificar (debe listar ~24 tablas, 0 permisos de escritura)
-- Conéctate como lector y prueba: INSERT debe fallar, SELECT debe funcionar.
-- Revocar si se necesita: REVOKE ALL ON ALL TABLES IN SCHEMA public FROM equipo_bi_lector; DROP ROLE equipo_bi_lector;
