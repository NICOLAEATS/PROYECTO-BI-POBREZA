-- =====================================================================
-- PROYECTO BI POBREZA MONETARIA PERU - MODELO ESTRELLA
-- Compatible: Neon (Postgres 16) y Supabase (Postgres 15)
-- Grano ENAHO: 1 fila = 1 hogar encuestado (Sumaria Módulo 34)
-- Grano BID:  1 fila = pais + anio + area (filtrado a Total)
-- Autor: equipo BI UAC - Cusco 2026
-- =====================================================================

-- Limpieza previa (solo primera vez)
DROP VIEW IF EXISTS vw_tasa_pobreza_ponderada CASCADE;
DROP VIEW IF EXISTS vw_bid_peru_serie CASCADE;
DROP VIEW IF EXISTS vw_comparativo_enaho_bid CASCADE;
DROP TABLE IF EXISTS fact_bid_pobreza CASCADE;
DROP TABLE IF EXISTS fact_hogar_pobreza CASCADE;
DROP TABLE IF EXISTS dim_pais CASCADE;
DROP TABLE IF EXISTS dim_condicion_pobreza CASCADE;
DROP TABLE IF EXISTS dim_estrato CASCADE;
DROP TABLE IF EXISTS dim_dominio CASCADE;
DROP TABLE IF EXISTS dim_departamento CASCADE;
DROP TABLE IF EXISTS dim_tiempo CASCADE;

-- ---------------- DIM_TIEMPO ----------------
CREATE TABLE dim_tiempo (
  anio SMALLINT PRIMARY KEY,
  CHECK (anio BETWEEN 2003 AND 2030)
);

-- ---------------- DIM_DEPARTAMENTO (UBIGEO DD) ----------------
-- UBIGEO: 6 dígitos DDPPDD. Departamento = LEFT(UBIGEO,2)
CREATE TABLE dim_departamento (
  cod_dep CHAR(2) PRIMARY KEY,
  nombre TEXT NOT NULL,
  region_natural TEXT -- Costa/Sierra/Selva/Lima-Callao referencial
);

INSERT INTO dim_departamento (cod_dep, nombre) VALUES
('01','Amazonas'),('02','Ancash'),('03','Apurimac'),('04','Arequipa'),
('05','Ayacucho'),('06','Cajamarca'),('07','Callao'),('08','Cusco'),
('09','Huancavelica'),('10','Huanuco'),('11','Ica'),('12','Junin'),
('13','La Libertad'),('14','Lambayeque'),('15','Lima'),('16','Loreto'),
('17','Madre de Dios'),('18','Moquegua'),('19','Pasco'),('20','Piura'),
('21','Puno'),('22','San Martin'),('23','Tacna'),('24','Tumbes'),
('25','Ucayali');

-- ---------------- DIM_DOMINIO (INEI, 1-8) ----------------
-- Validar con FichaTecnica.pdf dentro de 966-Modulo34.zip
-- Estándar INEI: 1=Costa Norte 2=Costa Centro 3=Costa Sur 4=Sierra Norte
-- 5=Sierra Centro 6=Sierra Sur 7=Selva 8=Lima Metropolitana
CREATE TABLE dim_dominio (
  dominio_id SMALLINT PRIMARY KEY,
  nombre TEXT NOT NULL,
  CHECK (dominio_id BETWEEN 1 AND 8)
);

INSERT INTO dim_dominio (dominio_id, nombre) VALUES
(1,'Costa Norte'),(2,'Costa Centro'),(3,'Costa Sur'),
(4,'Sierra Norte'),(5,'Sierra Centro'),(6,'Sierra Sur'),
(7,'Selva'),(8,'Lima Metropolitana');

-- ---------------- DIM_ESTRATO (1-8) ----------------
CREATE TABLE dim_estrato (
  estrato_id SMALLINT PRIMARY KEY,
  descripcion TEXT NOT NULL,
  CHECK (estrato_id BETWEEN 1 AND 8)
);

INSERT INTO dim_estrato (estrato_id, descripcion) VALUES
(1,'Estrato 1'),(2,'Estrato 2'),(3,'Estrato 3'),(4,'Estrato 4'),
(5,'Estrato 5'),(6,'Estrato 6'),(7,'Estrato 7'),(8,'Estrato 8');

-- ---------------- DIM_CONDICION_POBREZA ----------------
-- ENAHO Sumaria: POBREZA 1=pobre extremo 2=pobre no extremo 3=no pobre
-- Verificado en muestra Sumaria-2024.csv (n=20000: 1=933, 2=3094, 3=15973)
CREATE TABLE dim_condicion_pobreza (
  pobreza_id SMALLINT PRIMARY KEY,
  etiqueta TEXT NOT NULL,
  es_pobre BOOLEAN NOT NULL,
  es_extremo BOOLEAN NOT NULL,
  CHECK (pobreza_id IN (1,2,3))
);

INSERT INTO dim_condicion_pobreza VALUES
(1,'Pobre extremo', TRUE, TRUE),
(2,'Pobre no extremo', TRUE, FALSE),
(3,'No pobre', FALSE, FALSE);

-- ---------------- FACT_HOGAR_POBREZA (ENAHO) ----------------
-- Solo columnas BI-relevantes (~25 de 163) para no exceder free-tier
-- 500MB Supabase / 3GB Neon. Resto de GRU*/ING* se agregan si se requiere.
CREATE TABLE fact_hogar_pobreza (
  hogar_sk BIGSERIAL PRIMARY KEY,
  anio SMALLINT NOT NULL REFERENCES dim_tiempo(anio),
  mes SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  conglome TEXT NOT NULL,
  vivienda TEXT NOT NULL,
  hogar TEXT NOT NULL,
  ubigeo CHAR(6) NOT NULL,
  cod_dep CHAR(2) GENERATED ALWAYS AS (LEFT(ubigeo, 2)) STORED REFERENCES dim_departamento(cod_dep),
  dominio_id SMALLINT NOT NULL REFERENCES dim_dominio(dominio_id),
  estrato_id SMALLINT NOT NULL REFERENCES dim_estrato(estrato_id),
  mieperho SMALLINT,              -- miembros por hogar
  totmieho SMALLINT,
  percepho SMALLINT,
  -- Ingreso / gasto anual hogar (soles)
  inghog1d NUMERIC(14,2),         -- ingreso neto hogar
  inghog2d NUMERIC(14,2),
  gashog1d NUMERIC(14,2),         -- gasto bruto hogar
  gashog2d NUMERIC(14,2),
  ingmo1hd NUMERIC(14,2),         -- ingreso monetario
  ingmo2hd NUMERIC(14,2),
  estrsocial SMALLINT,            -- estrato social
  ld NUMERIC(12,8),               -- línea de pobreza extrema? (deflactor)
  linpe NUMERIC(12,2),            -- línea pobreza extrema
  linea NUMERIC(12,2),            -- línea pobreza total
  pobreza_id SMALLINT NOT NULL REFERENCES dim_condicion_pobreza(pobreza_id),
  factor07 DOUBLE PRECISION NOT NULL CHECK (factor07 > 0), -- factor expansión
  lineav NUMERIC(12,2),
  pobrezav SMALLINT CHECK (pobrezav IN (1,2,3,4)),
  UNIQUE (anio, conglome, vivienda, hogar)
);

CREATE INDEX idx_fact_anio ON fact_hogar_pobreza (anio);
CREATE INDEX idx_fact_dep ON fact_hogar_pobreza (cod_dep);
CREATE INDEX idx_fact_dominio ON fact_hogar_pobreza (dominio_id);
CREATE INDEX idx_fact_pobreza ON fact_hogar_pobreza (pobreza_id);
CREATE INDEX idx_fact_ubigeo ON fact_hogar_pobreza (ubigeo);

COMMENT ON TABLE fact_hogar_pobreza IS 'Grano hogar ENAHO Sumaria. Tasas oficiales con FACTOR07*MIEPERHO (personas).';
COMMENT ON COLUMN fact_hogar_pobreza.factor07 IS 'Factor de expansión INEI. Tasa oficial = SUM(CASE WHEN pobreza IN (1,2) THEN factor07*mieperho END)/SUM(factor07*mieperho). Validado 2024: 27.58%.';

-- ---------------- DIM_PAIS + FACT_BID ----------------
CREATE TABLE dim_pais (
  isoalpha3 CHAR(3) PRIMARY KEY,
  nombre TEXT NOT NULL
);

INSERT INTO dim_pais VALUES
('PER','Perú'),('CHL','Chile'),('COL','Colombia'),('ECU','Ecuador'),
('ARG','Argentina'),('BRA','Brasil'),('MEX','México'),('URY','Uruguay');

CREATE TABLE fact_bid_pobreza (
  bid_sk BIGSERIAL PRIMARY KEY,
  isoalpha3 CHAR(3) NOT NULL REFERENCES dim_pais(isoalpha3),
  anio SMALLINT NOT NULL CHECK (anio BETWEEN 2003 AND 2030),
  area TEXT NOT NULL CHECK (area IN ('urban','rural','Total')),
  indicator TEXT NOT NULL DEFAULT 'pobreza',
  value DOUBLE PRECISION NOT NULL CHECK (value BETWEEN 0 AND 1),
  se DOUBLE PRECISION,
  cv DOUBLE PRECISION,
  sample DOUBLE PRECISION,
  source TEXT,
  UNIQUE (isoalpha3, anio, area, indicator)
);

CREATE INDEX idx_bid_pais_anio ON fact_bid_pobreza (isoalpha3, anio);
CREATE INDEX idx_bid_area ON fact_bid_pobreza (area);

-- ---------------- VISTAS PARA POWER BI ----------------
-- Tasa ponderada ENAHO: usar SIEMPRE factor07 * mieperho (personas, metodología INEI)
-- Tasa oficial 2024 validada: 27.58% persona-ponderada (vs 21.85% solo-hogar)
CREATE OR REPLACE VIEW vw_tasa_pobreza_ponderada AS
SELECT
  f.anio,
  f.cod_dep,
  d.nombre AS departamento,
  f.dominio_id,
  dom.nombre AS dominio,
  f.estrato_id,
  COUNT(*) AS n_hogares_muestra,
  SUM(f.factor07) AS hogares_expandidos,
  SUM(f.factor07 * f.mieperho) AS poblacion_expandida,
  SUM(CASE WHEN f.pobreza_id IN (1,2) THEN f.factor07 * f.mieperho ELSE 0 END) / NULLIF(SUM(f.factor07 * f.mieperho),0) AS tasa_pobreza,
  SUM(CASE WHEN f.pobreza_id = 1 THEN f.factor07 * f.mieperho ELSE 0 END) / NULLIF(SUM(f.factor07 * f.mieperho),0) AS tasa_pobreza_extrema,
  AVG(f.linea) AS linea_promedio,
  AVG(f.linpe) AS linpe_promedio,
  AVG(f.inghog1d) AS ingreso_promedio_hogar
FROM fact_hogar_pobreza f
JOIN dim_departamento d ON d.cod_dep = f.cod_dep
JOIN dim_dominio dom ON dom.dominio_id = f.dominio_id
GROUP BY 1,2,3,4,5,6;

-- Serie BID Perú lista para gráfico (ya filtrada a Total demográfico)
CREATE OR REPLACE VIEW vw_bid_peru_serie AS
SELECT anio, area, indicator, value AS tasa_pobreza_bid, se, cv, sample, source
FROM fact_bid_pobreza
WHERE isoalpha3 = 'PER'
ORDER BY anio, area;

-- Comparativo ENAHO vs BID (nacional anual, área Total)
-- ENAHO con ponderador personas = FACTOR07 * MIEPERHO (metodología INEI)
CREATE OR REPLACE VIEW vw_comparativo_enaho_bid AS
SELECT
  e.anio,
  SUM(CASE WHEN e.pobreza_id IN (1,2) THEN e.factor07 * e.mieperho ELSE 0 END) / NULLIF(SUM(e.factor07 * e.mieperho),0) AS tasa_enaho,
  MAX(b.value) AS tasa_bid_total
FROM fact_hogar_pobreza e
LEFT JOIN fact_bid_pobreza b
  ON b.isoalpha3='PER' AND b.anio=e.anio AND b.area='Total' AND b.indicator='pobreza'
GROUP BY e.anio
ORDER BY e.anio;

-- ---------------- CARGA (ejemplos) ----------------
-- Desde psql / Neon SQL Editor:
-- \copy dim_tiempo(anio) FROM 'dim_tiempo.csv' CSV HEADER;
-- \copy fact_hogar_pobreza(anio,mes,conglome,vivienda,hogar,ubigeo,dominio_id,estrato_id,mieperho,totmieho,percepho,inghog1d,inghog2d,gashog1d,gashog2d,ingmo1hd,ingmo2hd,estrsocial,ld,linpe,linea,pobreza_id,factor07,lineav,pobrezav) FROM 'fact_2017_2025.csv' CSV HEADER;
-- \copy fact_bid_pobreza(isoalpha3,anio,area,indicator,value,se,cv,sample,source) FROM 'bid_filtrado.csv' CSV HEADER;
