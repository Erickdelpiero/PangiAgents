-- ============================================================
-- 010 — Espejo de doctores, clínicas y sus procedimientos
-- ============================================================
-- Extiende el espejo local de Pangi con los proveedores. NOVA lee
-- de aquí en lugar de su lista MOCK_PROVIDERS de 18 doctores
-- inventados.
--
-- FUENTE: GET /api/common/doctors?limit=100  (pública, sin auth)
--   Una sola llamada devuelve los 28 con sus clínicas y
--   procedimientos anidados. Verificado: total declarado 28,
--   devueltos 28.
--
-- Lo llena el workflow 06_pangi_catalog_sync, junto al resto del
-- catálogo: mismo origen, misma cadencia, misma bitácora.
--
-- ⚠️ Los horarios NO se sincronizan. date-slots depende de
--    doctor + clínica + fecha y cambia constantemente; las
--    combinaciones son miles. Se consultan en vivo (F3-C).
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

-- ── 1. DOCTORES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pangi_doctors (
    pangi_id            VARCHAR(24) PRIMARY KEY,
    first_name          VARCHAR(150) NOT NULL,
    last_name           VARCHAR(150),
    designation         VARCHAR(150),   -- especialidad; NULL en 7 de 28
    professional_title  VARCHAR(200),   -- "General Dentist", "Prosthodontist"
    gender              VARCHAR(20),
    profile_pic         TEXT,
    about               TEXT,
    years_experience    VARCHAR(40),    -- area_of_expertise.name → "5 - 10"
    degrees             VARCHAR(120),   -- dr_degree unido → "MS, DDS"
    license_number      VARCHAR(80),
    languages           VARCHAR(250),   -- solo 3 de 28 lo tienen poblado

    -- Modalidades desde appointment[].code
    accepts_in_person   BOOLEAN DEFAULT FALSE,
    accepts_online      BOOLEAN DEFAULT FALSE,

    -- Agendable = puede recibir una cita por alguna vía.
    -- Presencial exige clínica (date-slots pide clinic_address).
    -- Video NO la exige: para eso existe slots-online.
    is_bookable         BOOLEAN DEFAULT FALSE,

    average_rate        NUMERIC(3,2) DEFAULT 0,
    review_count        INTEGER      DEFAULT 0,
    is_approve          BOOLEAN DEFAULT FALSE,
    status              VARCHAR(30),
    practice_name       VARCHAR(200),
    website             TEXT,
    synced_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pangi_doc_designation ON pangi_doctors (designation);
CREATE INDEX IF NOT EXISTS idx_pangi_doc_bookable    ON pangi_doctors (is_bookable)
    WHERE is_bookable = TRUE;

COMMENT ON TABLE pangi_doctors IS
    'Espejo de /api/common/doctors. 28 doctores, 20 agendables (ago 2026).';
COMMENT ON COLUMN pangi_doctors.designation IS
    'Especialidad. NULL en perfiles incompletos: esos doctores no aparecen en '
    'ninguna búsqueda por especialidad, que es el comportamiento correcto.';
COMMENT ON COLUMN pangi_doctors.is_bookable IS
    '(presencial Y con clínica) O (video). Un doctor sin clínica pero con video '
    'SÍ es agendable vía slots-online.';
COMMENT ON COLUMN pangi_doctors.average_rate IS
    'Hoy 0 en los 28: Pangi aún no tiene reseñas de pacientes. Se muestra '
    'years_experience en su lugar hasta que haya datos reales.';


-- ── 2. CLÍNICAS ─────────────────────────────────────────────
-- El _id de la clínica es lo que viaja como `clinic_address` en
-- date-slots y en la creación de la cita. Es el dato operativo
-- más importante de esta migración.
CREATE TABLE IF NOT EXISTS pangi_clinics (
    pangi_id          VARCHAR(24) PRIMARY KEY,
    doctor_pangi_id   VARCHAR(24) NOT NULL
                      REFERENCES pangi_doctors(pangi_id) ON DELETE CASCADE,
    label             VARCHAR(500),   -- campo `clinic`: dirección completa
    name              VARCHAR(250),   -- nombre comercial; suele venir vacío
    address1          VARCHAR(250),
    address2          VARCHAR(250),
    city              VARCHAR(150),   -- EXACTO como en pangi_cities
    state             VARCHAR(150),
    country_name      VARCHAR(100),   -- country_name.name
    latitude          NUMERIC(11,7),
    longitude         NUMERIC(11,7),
    synced_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pangi_clinic_doctor ON pangi_clinics (doctor_pangi_id);
CREATE INDEX IF NOT EXISTS idx_pangi_clinic_city   ON pangi_clinics (city);

COMMENT ON COLUMN pangi_clinics.pangi_id IS
    'Se pasa como clinic_address en date-slots y en add-appointment.';
COMMENT ON COLUMN pangi_clinics.city IS
    'Coincide con pangi_cities.city. La API de doctores NO filtra por ciudad '
    '(verificado: location=Bogota devolvió 16 dentistas de todo el mundo), '
    'así que el filtro se hace aquí.';


-- ── 3. PROCEDIMIENTOS QUE OFRECE CADA DOCTOR ────────────────
-- Doble propósito:
--   1. Saber qué doctor ofrece el procedimiento que el paciente pidió
--   2. Es la fuente del desplegable "Motivo de la Visita" en la web
--      de Pangi — NO get-treatment-reason, que devuelve vacío en
--      todos los doctores (verificado).
CREATE TABLE IF NOT EXISTS pangi_doctor_procedures (
    id                SERIAL PRIMARY KEY,
    doctor_pangi_id   VARCHAR(24) NOT NULL
                      REFERENCES pangi_doctors(pangi_id) ON DELETE CASCADE,
    name              VARCHAR(250) NOT NULL,  -- string EXACTO; va en visit_reason
    source            VARCHAR(20),            -- 'system' = del catálogo
                                              -- 'doctor' = agregado por él
    synced_at         TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (doctor_pangi_id, name)
);

CREATE INDEX IF NOT EXISTS idx_pangi_docproc_name   ON pangi_doctor_procedures (name);
CREATE INDEX IF NOT EXISTS idx_pangi_docproc_doctor ON pangi_doctor_procedures (doctor_pangi_id);

COMMENT ON COLUMN pangi_doctor_procedures.name IS
    'Valor EXACTO. Viaja como visit_reason al crear la cita.';
COMMENT ON COLUMN pangi_doctor_procedures.source IS
    'system = está en el catálogo de la especialidad. doctor = lo agregó el '
    'médico porque el catálogo no lo tenía (ej. Rhinoplasty antes de que se '
    'cargaran los estéticos).';


-- ── 4. BITÁCORA: columnas para doctores ─────────────────────
ALTER TABLE pangi_catalog_sync_log
    ADD COLUMN IF NOT EXISTS doctors_seen    INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS clinics_seen    INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS doctors_status  VARCHAR(20);

COMMENT ON COLUMN pangi_catalog_sync_log.doctors_status IS
    'ok | skipped | failed. Independiente del catálogo: una respuesta mala de '
    'doctores no debe impedir que se sincronicen especialidades y ciudades.';


-- ── 5. VISTA PARA NOVA ──────────────────────────────────────
-- Una fila por doctor+clínica: es la unidad real de agendamiento,
-- porque date-slots necesita AMBOS. Un doctor con dos clínicas
-- aparece dos veces, que es lo correcto: son dos opciones
-- distintas para el paciente.
CREATE OR REPLACE VIEW v_pangi_bookable AS
SELECT
    d.pangi_id            AS doctor_id,
    d.first_name,
    d.last_name,
    d.designation         AS specialty_name,
    d.professional_title,
    d.gender,
    d.years_experience,
    d.degrees,
    d.profile_pic,
    d.accepts_in_person,
    d.accepts_online,
    c.pangi_id            AS clinic_id,     -- va como clinic_address
    c.city,
    c.state,
    c.country_name,
    c.label               AS clinic_label
FROM pangi_doctors d
LEFT JOIN pangi_clinics c ON c.doctor_pangi_id = d.pangi_id
WHERE d.is_bookable = TRUE
  AND d.is_approve  = TRUE;

COMMENT ON VIEW v_pangi_bookable IS
    'Doctores agendables por clínica. LEFT JOIN a propósito: un doctor solo-video '
    'no tiene clínica y aparece con clinic_id NULL — sigue siendo agendable '
    'vía slots-online.';

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT table_name FROM information_schema.tables
WHERE table_schema='public'
  AND table_name IN ('pangi_doctors','pangi_clinics','pangi_doctor_procedures')
ORDER BY table_name;
-- Esperado: las 3

SELECT COUNT(*) AS vista_creada FROM information_schema.views
WHERE table_schema='public' AND table_name='v_pangi_bookable';
-- Esperado: 1

SELECT
  (SELECT COUNT(*) FROM pangi_doctors)            AS doctores,
  (SELECT COUNT(*) FROM pangi_clinics)            AS clinicas,
  (SELECT COUNT(*) FROM pangi_doctor_procedures)  AS procedimientos;
-- Esperado: 0, 0, 0 — las llena el workflow 06

SELECT column_name FROM information_schema.columns
WHERE table_name='pangi_catalog_sync_log'
  AND column_name IN ('doctors_seen','clinics_seen','doctors_status')
ORDER BY column_name;
-- Esperado: las 3

-- ============================================================
-- DESPUÉS DE LA PRIMERA SINCRONIZACIÓN, esperar aprox.:
--   doctores        28  (20 con is_bookable = TRUE)
--   clínicas        22  (Bogota 6, Medellín 3, Boynton Beach 2...)
--   procedimientos  ~120
--
-- Y estas consultas deberían cuadrar con lo ya conocido:
--
--   SELECT designation, COUNT(*) FILTER (WHERE is_bookable) AS agendables,
--          COUNT(*) AS total
--   FROM pangi_doctors GROUP BY designation ORDER BY total DESC;
--   -- Dental Care 16 · sin designation 7 · Plastic and Reconstructive 2
--
--   SELECT city, COUNT(DISTINCT doctor_id) FROM v_pangi_bookable
--   WHERE specialty_name = 'Dental Care' GROUP BY city ORDER BY 2 DESC;
--   -- Bogota debería encabezar
-- ============================================================
