-- ============================================================
-- 009 — Orden de presentación de procedimientos
-- ============================================================
-- El motor de SAGE numera la lista por índice del array:
--
--   procs.map((p, i) => `${i + 1}. ${procName(p)}`)
--
-- y matchProcedure acepta ese número como respuesta válida:
--
--   if (!isNaN(num) && num >= 1 && num <= procs.length)
--     matched = procs[num - 1];
--
-- Es decir: EL ORDEN DEL ARRAY ES LO QUE EL PACIENTE VE COMO
-- "1.", "2.", "3.". No es cosmético.
--
-- El orden del literal NO es alfabético — es curado. Empieza por
-- extracciones e implantes (lo más consultado) y deja
-- blanqueamiento casi al final.
--
-- Si getProcedures leyera de la base con ORDER BY procedure_key,
-- la lista se reordenaría alfabéticamente y "Blanqueamiento
-- Dental" saltaría de la posición 11 a la 1. Cambio de
-- comportamiento silencioso, sin error, difícil de rastrear.
--
-- Esta migración traslada el orden exacto del literal a la base.
--
-- ORIGEN DE LOS DATOS: extraídos programáticamente de
-- getProcedures() en el jsCode del motor de SAGE que corre en n8n.
-- No se transcribió nada a mano.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

ALTER TABLE knowledge_base
    ADD COLUMN IF NOT EXISTS display_order INTEGER;

COMMENT ON COLUMN knowledge_base.display_order IS
    'Posición en la lista que ve el paciente. Determina el número con el que '
    'puede responder. Debe ser consecutivo desde 1 dentro de cada especialidad.';

-- ── DENTAL ── orden curado, no alfabético
UPDATE knowledge_base SET display_order = 1 WHERE procedure_key = 'extraccion_simple';
UPDATE knowledge_base SET display_order = 2 WHERE procedure_key = 'extraccion_muela_juicio';
UPDATE knowledge_base SET display_order = 3 WHERE procedure_key = 'implante_dental';
UPDATE knowledge_base SET display_order = 4 WHERE procedure_key = 'protesis_completa';
UPDATE knowledge_base SET display_order = 5 WHERE procedure_key = 'carillas_veneers';
UPDATE knowledge_base SET display_order = 6 WHERE procedure_key = 'ortodoncia_brackets';
UPDATE knowledge_base SET display_order = 7 WHERE procedure_key = 'ortodoncia_invisible';
UPDATE knowledge_base SET display_order = 8 WHERE procedure_key = 'endodoncia';
UPDATE knowledge_base SET display_order = 9 WHERE procedure_key = 'corona_dental';
UPDATE knowledge_base SET display_order = 10 WHERE procedure_key = 'limpieza_profunda';
UPDATE knowledge_base SET display_order = 11 WHERE procedure_key = 'blanqueamiento';
UPDATE knowledge_base SET display_order = 12 WHERE procedure_key = 'puente_dental';

-- ── PLASTIC_SURGERY ── orden curado, no alfabético
UPDATE knowledge_base SET display_order = 1 WHERE procedure_key = 'rinoplastia';
UPDATE knowledge_base SET display_order = 2 WHERE procedure_key = 'abdominoplastia';
UPDATE knowledge_base SET display_order = 3 WHERE procedure_key = 'liposuccion';
UPDATE knowledge_base SET display_order = 4 WHERE procedure_key = 'aumento_mamario';
UPDATE knowledge_base SET display_order = 5 WHERE procedure_key = 'reduccion_mamaria';
UPDATE knowledge_base SET display_order = 6 WHERE procedure_key = 'bichectomia';
UPDATE knowledge_base SET display_order = 7 WHERE procedure_key = 'blefaroplastia';
UPDATE knowledge_base SET display_order = 8 WHERE procedure_key = 'otoplastia';
UPDATE knowledge_base SET display_order = 9 WHERE procedure_key = 'lifting_facial';
UPDATE knowledge_base SET display_order = 10 WHERE procedure_key = 'bbl';
-- Evita que dos procedimientos de la misma especialidad compartan
-- posición: rompería la numeración que el paciente usa para responder.
CREATE UNIQUE INDEX IF NOT EXISTS idx_kb_display_order
    ON knowledge_base (specialty, display_order)
    WHERE display_order IS NOT NULL;

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT COUNT(*) AS sin_orden FROM knowledge_base WHERE display_order IS NULL;
-- Esperado: 0

-- Consecutivo desde 1 en cada especialidad, sin huecos ni saltos
SELECT specialty, MIN(display_order) AS primero, MAX(display_order) AS ultimo,
       COUNT(*) AS total,
       (MAX(display_order) = COUNT(*) AND MIN(display_order) = 1) AS consecutivo
FROM knowledge_base GROUP BY specialty ORDER BY specialty;
-- Esperado: dental 1..12 (12, true) · plastic_surgery 1..10 (10, true)

-- La lista tal como la verá el paciente en español
SELECT specialty, display_order, name_es
FROM knowledge_base ORDER BY specialty, display_order;

-- Lo que devolverá getProcedures: KB ∩ catálogo activo, en orden
SELECT kb.specialty, kb.display_order, kb.procedure_key, kb.name_es,
       kb.pangi_procedure_name
FROM knowledge_base kb
JOIN pangi_specialties s ON s.name = kb.pangi_specialty_name AND s.is_visible = TRUE
JOIN pangi_procedures  p ON p.specialty_pangi_id = s.pangi_id
                        AND p.name = kb.pangi_procedure_name
ORDER BY kb.specialty, kb.display_order;
-- Esperado: 22 filas, orden idéntico al literal del motor
