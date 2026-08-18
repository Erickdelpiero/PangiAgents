-- ============================================================
-- 004 — Integración con Pangi: mapeo de catálogos e identidad
-- ============================================================
-- Prepara el schema para que los agentes lean el catálogo real
-- de Pangi y escriban solicitudes de tratamiento en su API.
--
-- Contratos verificados contra producción (DevTools, ago 2026):
--   - Especialidades y procedimientos se identifican por STRING
--     EXACTO en inglés, NO por ObjectId. Los procedimientos viven
--     dentro de sub_speciality, que es un string con JSON adentro.
--   - sub_speciality_es y sub_speciality_pt están vacíos en las 22
--     especialidades: Pangi es dueño de la taxonomía (inglés),
--     esta KB es dueña de las traducciones.
--
-- ⚠️ Los strings de pangi_* deben copiarse LITERALMENTE del API.
--    Varios llevan guion largo (–, U+2013) y uno lleva espacio
--    final. Escribirlos a mano rompe el mapeo en silencio.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

-- ── 1. IDENTIDAD DEL PACIENTE ───────────────────────────────
-- Hoy la identidad es phone='tg:<chatId>'. Con el widget dentro
-- de pangi.com el usuario llega autenticado por JWT, así que el
-- ancla pasa a ser el ObjectId de Pangi (24 chars hex).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS pangi_user_id VARCHAR(24);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_pangi_id
    ON users (pangi_user_id)
    WHERE pangi_user_id IS NOT NULL;

-- phone deja de ser obligatorio: en el widget puede no estar
-- disponible al abrir la sesión. El UNIQUE se conserva y admite
-- múltiples NULL sin colisionar.
ALTER TABLE users
    ALTER COLUMN phone DROP NOT NULL;

COMMENT ON COLUMN users.pangi_user_id IS
    'ObjectId del paciente en Pangi. Ancla de identidad para el widget.';


-- ── 2. VÍNCULO CON post_treatment ───────────────────────────
-- Al confirmar, SAGE hace UNA llamada a
-- POST /api/patient/post-treatment-concern y guarda aquí el _id
-- devuelto. Ese id es lo que ATLAS usa después para leer los
-- PreTreatmentEstimate del médico.
ALTER TABLE medical_intake
    ADD COLUMN IF NOT EXISTS pangi_post_treatment_id VARCHAR(24),
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_intake_pangi_id
    ON medical_intake (pangi_post_treatment_id)
    WHERE pangi_post_treatment_id IS NOT NULL;

COMMENT ON COLUMN medical_intake.pangi_post_treatment_id IS
    'ObjectId devuelto por post-treatment-concern. NULL = aún no publicado.';

-- Estados de medical_intake.status tras la integración:
--   in_progress → conversación en curso
--   submitted   → el paciente confirmó (borrador cerrado)
--   published   → creado en Pangi (pangi_post_treatment_id presente)
--   failed      → el paciente confirmó pero la API falló; reintentable
-- Antes de esta migración 'submitted' era terminal. Ahora no lo es.


-- ── 3. MAPEO DE TAXONOMÍA ───────────────────────────────────
ALTER TABLE knowledge_base
    ADD COLUMN IF NOT EXISTS pangi_specialty_name  VARCHAR(100),
    ADD COLUMN IF NOT EXISTS pangi_procedure_name  VARCHAR(200);

COMMENT ON COLUMN knowledge_base.pangi_specialty_name IS
    'Valor exacto del campo category en post-treatment-concern.';
COMMENT ON COLUMN knowledge_base.pangi_procedure_name IS
    'Valor exacto dentro del array procedures. NULL = no existe aún en Pangi.';

-- Especialidades (nombres exactos del API)
UPDATE knowledge_base SET pangi_specialty_name = 'Dental Care'
    WHERE specialty = 'dental';
UPDATE knowledge_base SET pangi_specialty_name = 'Plastic and Reconstructive Surgery'
    WHERE specialty = 'plastic_surgery';

-- ── 3a. Dental: 12/12 mapeados ──
-- Los 7 primeros son los procedimientos "comerciales" que los
-- médicos efectivamente seleccionan en su perfil.
UPDATE knowledge_base SET pangi_procedure_name = 'Dental Implants'
    WHERE procedure_key = 'implante_dental';
UPDATE knowledge_base SET pangi_procedure_name = 'Crowns and Bridges'
    WHERE procedure_key = 'corona_dental';
UPDATE knowledge_base SET pangi_procedure_name = 'Crowns and Bridges'
    WHERE procedure_key = 'puente_dental';
UPDATE knowledge_base SET pangi_procedure_name = 'Veneers'
    WHERE procedure_key = 'carillas_veneers';
UPDATE knowledge_base SET pangi_procedure_name = 'Teeth Whitening'
    WHERE procedure_key = 'blanqueamiento';
UPDATE knowledge_base SET pangi_procedure_name = 'Orthodontics (Braces, Invisalign)'
    WHERE procedure_key = 'ortodoncia_brackets';
UPDATE knowledge_base SET pangi_procedure_name = 'Orthodontics (Braces, Invisalign)'
    WHERE procedure_key = 'ortodoncia_invisible';
UPDATE knowledge_base SET pangi_procedure_name = 'Root Canal Therapy'
    WHERE procedure_key = 'endodoncia';

-- Los 4 siguientes solo existen en la lista granular de Pangi
-- (48 ítems tipo códigos de facturación). Ningún médico los tiene
-- seleccionados hoy, así que una solicitud con estos podría no
-- alcanzar a ningún proveedor. Verificar cómo Pangi rutea las
-- solicitudes antes de darlos por buenos.
UPDATE knowledge_base SET pangi_procedure_name = 'Simple tooth extraction (erupted)'
    WHERE procedure_key = 'extraccion_simple';
UPDATE knowledge_base SET pangi_procedure_name = 'Surgical extraction (impacted/sectioned)'
    WHERE procedure_key = 'extraccion_muela_juicio';
UPDATE knowledge_base SET pangi_procedure_name = 'Scaling & root planing – per quadrant (SRP)'
    WHERE procedure_key = 'limpieza_profunda';
UPDATE knowledge_base SET pangi_procedure_name = 'Complete denture – maxillary or mandibular'
    WHERE procedure_key = 'protesis_completa';

-- ── 3b. Cirugía plástica: 0/10 mapeados ──
-- El catálogo de Pangi bajo esta especialidad es RECONSTRUCTIVO
-- (reconstrucción mamaria, mano, quemaduras, labio leporino,
-- microcirugía). Los 10 procedimientos de esta KB son ESTÉTICOS.
-- Solapamiento: cero.
--
-- Evidencia de que el catálogo va detrás de la realidad: el
-- Dr. Miguel Dávila (cirujano plástico en Lima) tiene "Rhinoplasty"
-- con type:"doctor" — tuvo que agregarlo él mismo.
--
-- Quedan en NULL a propósito. Se pueblan cuando el CEO de Pangi agregue
-- estos procedimientos desde admin.pangi.com:
--   Rhinoplasty · Liposuction · Breast Augmentation · Brazilian
--   Butt Lift (BBL) · Abdominoplasty (Tummy Tuck) · Blepharoplasty
--   (Eyelid Surgery) · Otoplasty (Ear Surgery) · Facelift ·
--   Buccal Fat Removal · Breast Reduction
--
-- Mientras sigan en NULL, SAGE no puede crear solicitudes de
-- cirugía plástica en Pangi.


-- ── 4. CIUDADES ─────────────────────────────────────────────
ALTER TABLE atlas_destinations
    ADD COLUMN IF NOT EXISTS pangi_city_name VARCHAR(100);

COMMENT ON COLUMN atlas_destinations.pangi_city_name IS
    'Valor exacto del array addresses. NULL = sin médicos activos en Pangi.';

-- Solo 3 de 10 destinos tienen médicos activos hoy.
-- Ojo: Pangi escribe "Bogota" SIN tilde.
UPDATE atlas_destinations SET pangi_city_name = 'Lima'     WHERE city = 'Lima';
UPDATE atlas_destinations SET pangi_city_name = 'Bogota'   WHERE city = 'Bogotá';
UPDATE atlas_destinations SET pangi_city_name = 'Medellín' WHERE city = 'Medellín';

-- Sin médicos activos: Ciudad de México, Cancún, Cartagena,
-- San José, Buenos Aires, Santo Domingo, Miami.
--
-- Nota sobre available-locations: devuelve ciudades derivadas de
-- geocodificar direcciones de clínicas, así que aparecen barrios
-- ("Balvanera", "Barracas" = Buenos Aires) y localidades menores
-- ("Alejandría", "Gachala", "Río Segundo"). No es una lista apta
-- para conversar con el paciente sin normalizar antes.

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT specialty,
       COUNT(*)                                              AS total,
       COUNT(pangi_procedure_name)                           AS mapeados,
       COUNT(*) - COUNT(pangi_procedure_name)                AS pendientes
FROM knowledge_base
GROUP BY specialty ORDER BY specialty;
-- Esperado: dental 12/12/0 · plastic_surgery 10/0/10

SELECT procedure_key, pangi_procedure_name
FROM knowledge_base
WHERE specialty = 'dental'
ORDER BY procedure_key;

SELECT city, pangi_city_name FROM atlas_destinations ORDER BY city;
-- Esperado: 3 con valor, 7 en NULL

SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_name = 'users' AND column_name IN ('phone','pangi_user_id');
-- Esperado: phone YES · pangi_user_id YES
