-- ============================================================
-- 006 — Catálogo sincronizado desde Pangi
-- ============================================================
-- Crea el destino local del catálogo de Pangi. Los agentes leen
-- de estas tablas, NUNCA llaman a la API de Pangi en el camino
-- crítico de la conversación.
--
-- Razones del diseño:
--   1. Latencia — cero HTTP mientras el paciente espera respuesta.
--   2. Resiliencia — si Pangi cae, los agentes siguen operando con
--      el último catálogo conocido en vez de romperse.
--   3. Consistencia — SAGE, NOVA y ATLAS ven exactamente lo mismo.
--
-- Las llena el workflow 06_pangi_catalog_sync (schedule horario).
-- Post-Azure se le suma un Webhook Trigger para frescura casi
-- instantánea; el schedule baja a diario como reconciliación.
--
-- FUENTES:
--   GET /api/common/speciality?lang=en   → specialties + procedures
--   GET /api/common/countries            → ciudades del catálogo curado
--   GET /api/common/available-locations  → ciudades con médicos reales
--
-- ⚠️ Una sola llamada a speciality trae los TRES idiomas
--    (verificado 18/08/2026: con lang=en igual vienen
--    sub_speciality_es y name_es). El parámetro lang solo cambia
--    displayName, que no usamos.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

-- ── 1. ESPECIALIDADES ───────────────────────────────────────
-- Espejo de las 22 especialidades de Pangi. La PK es el ObjectId
-- de Mongo: es el único identificador estable que expone la API.
CREATE TABLE IF NOT EXISTS pangi_specialties (
    pangi_id                    VARCHAR(24) PRIMARY KEY,
    name                        VARCHAR(150) NOT NULL,   -- inglés; va en el campo `category`
    name_es                     VARCHAR(150),
    name_pt                     VARCHAR(150),
    is_visible                  BOOLEAN     DEFAULT TRUE,
    allow_number_of_procedure   INTEGER     DEFAULT 1,
    doc_en                      TEXT,                    -- guía fotográfica (PDF)
    doc_es                      TEXT,
    doc_pt                      TEXT,
    logo                        TEXT,
    synced_at                   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pangi_spec_name    ON pangi_specialties (name);
CREATE INDEX IF NOT EXISTS idx_pangi_spec_visible ON pangi_specialties (is_visible)
    WHERE is_visible = TRUE;

COMMENT ON TABLE  pangi_specialties IS
    'Espejo de /api/common/speciality. Fuente de verdad: admin.pangi.com.';
COMMENT ON COLUMN pangi_specialties.name IS
    'Nombre en inglés. Es el valor EXACTO del campo category en post-treatment-concern.';
COMMENT ON COLUMN pangi_specialties.allow_number_of_procedure IS
    'Máx. procedimientos por solicitud. Dental=3, plástica=3, resto=1. SAGE debe respetarlo.';


-- ── 2. PROCEDIMIENTOS ───────────────────────────────────────
-- En Pangi los procedimientos NO son entidades: viven como strings
-- dentro de sub_speciality, que además es un STRING con JSON adentro.
-- Las traducciones son arreglos PARALELOS que se emparejan por
-- POSICIÓN — por eso `position` es parte del modelo, no un adorno.
--
-- Dental tiene 48 en inglés y 0 traducidos. Se guardan igual, con
-- name_es/name_pt en NULL: descartar la fila perdería el catálogo.
CREATE TABLE IF NOT EXISTS pangi_procedures (
    id                  SERIAL PRIMARY KEY,
    specialty_pangi_id  VARCHAR(24) NOT NULL
                        REFERENCES pangi_specialties(pangi_id) ON DELETE CASCADE,
    position            INTEGER     NOT NULL,   -- índice en sub_speciality
    name                VARCHAR(250) NOT NULL,  -- inglés; va en el array `procedures`
    name_es             VARCHAR(250),
    name_pt             VARCHAR(250),
    synced_at           TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (specialty_pangi_id, name)
);

CREATE INDEX IF NOT EXISTS idx_pangi_proc_specialty ON pangi_procedures (specialty_pangi_id);
CREATE INDEX IF NOT EXISTS idx_pangi_proc_name      ON pangi_procedures (name);

COMMENT ON TABLE  pangi_procedures IS
    'Procedimientos extraídos de sub_speciality. Requiere JSON.parse del string.';
COMMENT ON COLUMN pangi_procedures.position IS
    'Índice en el array original. Las traducciones se alinean por posición.';
COMMENT ON COLUMN pangi_procedures.name IS
    'Valor EXACTO del array procedures. Copiar literal: hay guiones largos (U+2013) y espacios finales.';


-- ── 3. CIUDADES ─────────────────────────────────────────────
-- Dos fuentes que NO coinciden, y ambas importan:
--
--   /countries           → catálogo curado (México, Rep. Dominicana...)
--   /available-locations → dónde hay médicos DE VERDAD
--
-- available-locations se deriva de geocodificar direcciones de
-- clínicas, así que aparecen barrios ("Balvanera", "Barracas" son
-- de Buenos Aires) y localidades menores ("Gachala", "Río Segundo").
-- No es una lista apta para conversar con el paciente sin normalizar.
--
-- Se guardan las DOS señales por separado en vez de una lista única:
-- así la política de qué ofrecer se decide en los agentes, sin
-- volver a tocar la sincronización.
CREATE TABLE IF NOT EXISTS pangi_cities (
    id            SERIAL PRIMARY KEY,
    country_code  VARCHAR(4)   NOT NULL,
    country_name  VARCHAR(100) NOT NULL,
    city          VARCHAR(150) NOT NULL,   -- EXACTO como lo espera `addresses`
    state         VARCHAR(150),
    in_catalog    BOOLEAN DEFAULT FALSE,   -- aparece en /countries
    has_doctors   BOOLEAN DEFAULT FALSE,   -- aparece en /available-locations
    synced_at     TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (country_code, city)
);

CREATE INDEX IF NOT EXISTS idx_pangi_cities_doctors ON pangi_cities (has_doctors)
    WHERE has_doctors = TRUE;
CREATE INDEX IF NOT EXISTS idx_pangi_cities_country ON pangi_cities (country_code);

COMMENT ON COLUMN pangi_cities.city IS
    'Valor EXACTO del array addresses. Pangi escribe "Bogota" SIN tilde y "Mexico City".';
COMMENT ON COLUMN pangi_cities.has_doctors IS
    'TRUE = hay médicos activos. Es la señal que deben usar los agentes para ofrecer destinos.';


-- ── 4. BITÁCORA DE SINCRONIZACIÓN ───────────────────────────
-- Sin esto, una sincronización que falla en silencio deja el
-- catálogo desactualizado sin ninguna señal. Es el modo de falla
-- clásico de este patrón: no falla ruidosamente, se desincroniza
-- callando.
CREATE TABLE IF NOT EXISTS pangi_catalog_sync_log (
    id               SERIAL PRIMARY KEY,
    started_at       TIMESTAMPTZ DEFAULT NOW(),
    finished_at      TIMESTAMPTZ,
    status           VARCHAR(20) NOT NULL,   -- ok | partial | failed
    specialties_seen INTEGER DEFAULT 0,
    procedures_seen  INTEGER DEFAULT 0,
    cities_seen      INTEGER DEFAULT 0,
    rows_deleted     INTEGER DEFAULT 0,
    error_message    TEXT,
    trigger_source   VARCHAR(20) DEFAULT 'schedule'  -- schedule | webhook | manual
);

CREATE INDEX IF NOT EXISTS idx_sync_log_started ON pangi_catalog_sync_log (started_at DESC);

COMMENT ON TABLE pangi_catalog_sync_log IS
    'Bitácora del workflow 06_pangi_catalog_sync. Revisar aquí si el catálogo se ve raro.';


-- ── 5. VISTA DE CONVENIENCIA ────────────────────────────────
-- Lo que los agentes consultan realmente: procedimientos activos
-- de las especialidades visibles, ya unidos y con el nombre en
-- español de la KB cuando existe mapeo.
CREATE OR REPLACE VIEW v_pangi_catalog AS
SELECT
    s.pangi_id                  AS specialty_id,
    s.name                      AS specialty_name,
    s.name_es                   AS specialty_name_es,
    s.allow_number_of_procedure,
    s.doc_es                    AS photo_guide_es,
    p.name                      AS procedure_name,
    p.name_es                   AS procedure_name_es,
    kb.procedure_key,                       -- NULL si la KB no lo cubre
    kb.procedure_name           AS kb_name_es
FROM pangi_specialties s
JOIN pangi_procedures  p  ON p.specialty_pangi_id = s.pangi_id
LEFT JOIN knowledge_base kb
       ON kb.pangi_procedure_name = p.name
      AND kb.pangi_specialty_name = s.name
WHERE s.is_visible = TRUE;

COMMENT ON VIEW v_pangi_catalog IS
    'Catálogo activo cruzado con la KB. procedure_key NULL = Pangi lo ofrece pero SAGE no sabe guiarlo.';

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('pangi_specialties','pangi_procedures',
                     'pangi_cities','pangi_catalog_sync_log')
ORDER BY table_name;
-- Esperado: las 4 tablas

SELECT COUNT(*) AS vista_creada
FROM information_schema.views
WHERE table_schema = 'public' AND table_name = 'v_pangi_catalog';
-- Esperado: 1

SELECT
  (SELECT COUNT(*) FROM pangi_specialties)       AS especialidades,
  (SELECT COUNT(*) FROM pangi_procedures)        AS procedimientos,
  (SELECT COUNT(*) FROM pangi_cities)            AS ciudades,
  (SELECT COUNT(*) FROM pangi_catalog_sync_log)  AS sincronizaciones;
-- Esperado: 0, 0, 0, 0 — las llena el workflow 06

-- ============================================================
-- DESPUÉS DE LA PRIMERA SINCRONIZACIÓN, esperar aprox.:
--   especialidades  22
--   procedimientos  ~150  (48 dental + 15 plástica + resto)
--   ciudades        ~35    (unión de countries y available-locations)
--
-- Y estas dos consultas deberían cuadrar con lo ya conocido:
--
--   SELECT specialty_name, COUNT(*) FROM v_pangi_catalog
--   GROUP BY specialty_name ORDER BY specialty_name;
--
--   SELECT procedure_name, procedure_key FROM v_pangi_catalog
--   WHERE specialty_name = 'Plastic and Reconstructive Surgery'
--   ORDER BY procedure_name;
--   -- 15 filas · 10 con procedure_key · 5 reconstructivos en NULL
-- ============================================================
