-- ============================================================
-- 008 — Nombres i18n de procedimientos en la knowledge base
-- ============================================================
-- Traslada a la base los nombres que el paciente ve en pantalla.
-- Hoy viven SOLO dentro del literal PROCEDURES del motor de SAGE:
--   { name: 'Extracción Simple', nameEn: 'Simple Tooth Extraction',
--     namePt: 'Extração Simples', key: 'extraccion_simple' }
--
-- POR QUÉ TRES COLUMNAS Y NO DOS:
-- knowledge_base.procedure_name NO es lo que se muestra. El motor
-- usa procData solo para critical_questions, required_info,
-- required_exams, typical_recovery_days y sage_intro_message.
-- El nombre visible sale del literal vía procName().
--
-- Y los valores DIFIEREN en tres procedimientos:
--   procedure_name                          |  literal (visible)
--   Endodoncia (Tratamiento de Conducto)    |  Endodoncia (Conducto)
--   Limpieza Dental Profunda (Periodoncia)  |  Limpieza Profunda (Periodoncia)
--   Ortodoncia Invisible (Alineadores)      |  Ortodoncia Invisible
--
-- Sembrar solo name_en/name_pt y reusar procedure_name como español
-- cambiaría el texto en pantalla de esos tres. Por eso también va
-- name_es: garantiza cero cambio de comportamiento.
--
-- procedure_name queda como etiqueta canónica interna. Las columnas
-- name_* son lo que el paciente lee.
--
-- ORIGEN DE LOS DATOS: extraídos programáticamente de getProcedures()
-- en el jsCode del motor de SAGE (verificado byte a byte contra la
-- versión que corre en n8n). No se transcribió nada a mano.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

ALTER TABLE knowledge_base
    ADD COLUMN IF NOT EXISTS name_es VARCHAR(150),
    ADD COLUMN IF NOT EXISTS name_en VARCHAR(150),
    ADD COLUMN IF NOT EXISTS name_pt VARCHAR(150);

COMMENT ON COLUMN knowledge_base.name_es IS
    'Nombre visible en español. Puede diferir de procedure_name: este es el que ve el paciente.';
COMMENT ON COLUMN knowledge_base.name_en IS
    'Nombre visible en inglés. Pangi no traduce procedimientos: esta KB es la fuente.';
COMMENT ON COLUMN knowledge_base.name_pt IS
    'Nombre visible en portugués.';

-- ── DENTAL (12) ──
UPDATE knowledge_base SET name_es = 'Extracción Simple', name_en = 'Simple Tooth Extraction', name_pt = 'Extração Simples'
    WHERE procedure_key = 'extraccion_simple';
UPDATE knowledge_base SET name_es = 'Extracción Muela del Juicio', name_en = 'Wisdom Tooth Extraction', name_pt = 'Extração do Siso'
    WHERE procedure_key = 'extraccion_muela_juicio';
UPDATE knowledge_base SET name_es = 'Implante Dental', name_en = 'Dental Implant', name_pt = 'Implante Dentário'
    WHERE procedure_key = 'implante_dental';
UPDATE knowledge_base SET name_es = 'Prótesis Dental Completa', name_en = 'Complete Dentures', name_pt = 'Prótese Dentária Completa'
    WHERE procedure_key = 'protesis_completa';
UPDATE knowledge_base SET name_es = 'Carillas / Veneers', name_en = 'Porcelain Veneers', name_pt = 'Facetas Dentárias'
    WHERE procedure_key = 'carillas_veneers';
UPDATE knowledge_base SET name_es = 'Ortodoncia Brackets', name_en = 'Traditional Braces', name_pt = 'Aparelho Dentário Fixo'
    WHERE procedure_key = 'ortodoncia_brackets';
UPDATE knowledge_base SET name_es = 'Ortodoncia Invisible', name_en = 'Clear Aligners (Invisalign)', name_pt = 'Alinhadores Invisíveis'
    WHERE procedure_key = 'ortodoncia_invisible';
UPDATE knowledge_base SET name_es = 'Endodoncia (Conducto)', name_en = 'Root Canal Treatment', name_pt = 'Tratamento de Canal'
    WHERE procedure_key = 'endodoncia';
UPDATE knowledge_base SET name_es = 'Corona Dental', name_en = 'Dental Crown', name_pt = 'Coroa Dentária'
    WHERE procedure_key = 'corona_dental';
UPDATE knowledge_base SET name_es = 'Limpieza Profunda (Periodoncia)', name_en = 'Deep Cleaning (Periodontics)', name_pt = 'Limpeza Profunda (Periodontia)'
    WHERE procedure_key = 'limpieza_profunda';
UPDATE knowledge_base SET name_es = 'Blanqueamiento Dental', name_en = 'Teeth Whitening', name_pt = 'Clareamento Dental'
    WHERE procedure_key = 'blanqueamiento';
UPDATE knowledge_base SET name_es = 'Puente Dental', name_en = 'Dental Bridge', name_pt = 'Ponte Dentária'
    WHERE procedure_key = 'puente_dental';

-- ── CIRUGÍA PLÁSTICA (10) ──
UPDATE knowledge_base SET name_es = 'Rinoplastia', name_en = 'Rhinoplasty (Nose Job)', name_pt = 'Rinoplastia'
    WHERE procedure_key = 'rinoplastia';
UPDATE knowledge_base SET name_es = 'Abdominoplastia', name_en = 'Tummy Tuck', name_pt = 'Abdominoplastia'
    WHERE procedure_key = 'abdominoplastia';
UPDATE knowledge_base SET name_es = 'Liposucción', name_en = 'Liposuction', name_pt = 'Lipoaspiração'
    WHERE procedure_key = 'liposuccion';
UPDATE knowledge_base SET name_es = 'Aumento de Busto', name_en = 'Breast Augmentation', name_pt = 'Aumento de Seios'
    WHERE procedure_key = 'aumento_mamario';
UPDATE knowledge_base SET name_es = 'Reducción de Busto', name_en = 'Breast Reduction', name_pt = 'Redução Mamária'
    WHERE procedure_key = 'reduccion_mamaria';
UPDATE knowledge_base SET name_es = 'Bichectomía', name_en = 'Bichectomy (Cheek Reduction)', name_pt = 'Bichectomia'
    WHERE procedure_key = 'bichectomia';
UPDATE knowledge_base SET name_es = 'Blefaroplastia (Párpados)', name_en = 'Blepharoplasty (Eyelids)', name_pt = 'Blefaroplastia (Pálpebras)'
    WHERE procedure_key = 'blefaroplastia';
UPDATE knowledge_base SET name_es = 'Otoplastia (Orejas)', name_en = 'Otoplasty (Ear Surgery)', name_pt = 'Otoplastia (Orelhas)'
    WHERE procedure_key = 'otoplastia';
UPDATE knowledge_base SET name_es = 'Lifting Facial', name_en = 'Facelift', name_pt = 'Lifting Facial'
    WHERE procedure_key = 'lifting_facial';
UPDATE knowledge_base SET name_es = 'BBL (Brazilian Butt Lift)', name_en = 'BBL (Brazilian Butt Lift)', name_pt = 'BBL (Brazilian Butt Lift)'
    WHERE procedure_key = 'bbl';
COMMIT;

-- ============================================================
-- NOTAS
-- ============================================================
-- 1. PROCEDURE_ALIASES (22 claves) se queda en el motor a propósito.
--    No es catálogo: es reconocimiento de lenguaje afinado a mano.
--    Pangi no tiene alias y no los tendrá. Si aparece un
--    procedimiento nuevo sin alias, matchProcedure igual lo
--    encuentra por nombre y por número de lista.
--
-- 2. Los tres idiomas quedan editables sin tocar un workflow. Antes
--    estaban incrustados en 70 KB de JavaScript dentro de un JSON.
--
-- 3. Desbalance conocido: bbl usa el mismo texto en los tres
--    idiomas, y rinoplastia comparte español y portugués. No está
--    roto, pero se puede pulir ahora que es una fila y no código.
-- ============================================================

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT COUNT(*) AS sin_traducir FROM knowledge_base
WHERE name_es IS NULL OR name_en IS NULL OR name_pt IS NULL;
-- Esperado: 0

SELECT specialty, procedure_key, name_es, name_en, name_pt
FROM knowledge_base ORDER BY specialty, procedure_key;
-- Esperado: 22 filas, ninguna vacía

-- Los tres casos donde el nombre visible difiere del canónico
SELECT procedure_key, procedure_name AS canonico, name_es AS visible
FROM knowledge_base
WHERE procedure_name IS DISTINCT FROM name_es
ORDER BY procedure_key;
-- Esperado: 3 filas (endodoncia, limpieza_profunda, ortodoncia_invisible)

-- Lo que SAGE podrá ofrecer: KB ∩ catálogo activo de Pangi
SELECT kb.specialty, COUNT(*) AS ofrecibles
FROM knowledge_base kb
JOIN pangi_specialties s ON s.name = kb.pangi_specialty_name AND s.is_visible = TRUE
JOIN pangi_procedures  p ON p.specialty_pangi_id = s.pangi_id
                        AND p.name = kb.pangi_procedure_name
GROUP BY kb.specialty ORDER BY kb.specialty;
-- Esperado: dental 12 · plastic_surgery 10
