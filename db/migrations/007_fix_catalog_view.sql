-- ============================================================
-- 007 — Corrección de v_pangi_catalog
-- ============================================================
-- PROBLEMA detectado en la primera sincronización real:
--   la vista devolvía 50 procedimientos dentales cuando la tabla
--   tiene 48. Los datos estaban bien; la vista multiplicaba filas.
--
-- CAUSA: el LEFT JOIN contra knowledge_base produce una fila por
-- cada coincidencia, y la KB distingue más fino que Pangi:
--
--   Crowns and Bridges                ← corona_dental Y puente_dental
--   Orthodontics (Braces, Invisalign) ← ortodoncia_brackets Y
--                                        ortodoncia_invisible
--
-- 48 + 2 duplicados = 50.
--
-- IMPACTO SI NO SE CORRIGE: al listar procedimientos, SAGE le
-- mostraría al paciente "Ortodoncia" y "Coronas y Puentes" DOS
-- VECES. Falla silenciosa, sin error, difícil de rastrear después.
--
-- SOLUCIÓN: agregar en vez de multiplicar. Una fila por
-- procedimiento real, con los procedure_key de la KB colapsados
-- en un array. No se pierde información: si un procedimiento de
-- Pangi corresponde a dos entradas de la KB, ambas quedan
-- visibles en procedure_keys.
--
-- Se usa DROP + CREATE porque cambia la forma de las columnas y
-- CREATE OR REPLACE no lo permite. Es seguro: la vista se creó en
-- la migración 006 y todavía ningún agente la consume.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

DROP VIEW IF EXISTS v_pangi_catalog;

CREATE VIEW v_pangi_catalog AS
SELECT
    s.pangi_id                          AS specialty_id,
    s.name                              AS specialty_name,      -- va en `category`
    s.name_es                           AS specialty_name_es,
    s.allow_number_of_procedure,
    s.doc_es                            AS photo_guide_es,
    p.position,
    p.name                              AS procedure_name,      -- va en `procedures`
    p.name_es                           AS procedure_name_es,
    p.name_pt                           AS procedure_name_pt,
    -- Los procedure_key de la KB que apuntan a este procedimiento.
    -- Normalmente 0 o 1; puede ser 2 cuando la KB distingue más
    -- fino que Pangi (brackets vs. invisible, corona vs. puente).
    ARRAY_REMOVE(ARRAY_AGG(kb.procedure_key ORDER BY kb.procedure_key), NULL)
                                        AS procedure_keys,
    -- FALSE = Pangi lo ofrece pero SAGE no sabe guiarlo:
    -- no hay preguntas clínicas ni exámenes definidos.
    (COUNT(kb.procedure_key) > 0)       AS in_kb
FROM pangi_specialties s
JOIN pangi_procedures  p  ON p.specialty_pangi_id = s.pangi_id
LEFT JOIN knowledge_base kb
       ON kb.pangi_procedure_name = p.name
      AND kb.pangi_specialty_name = s.name
WHERE s.is_visible = TRUE
GROUP BY s.pangi_id, s.name, s.name_es, s.allow_number_of_procedure,
         s.doc_es, p.position, p.name, p.name_es, p.name_pt;

COMMENT ON VIEW v_pangi_catalog IS
    'Catálogo activo de Pangi cruzado con la KB. Una fila por procedimiento. '
    'in_kb = FALSE significa que Pangi lo ofrece pero SAGE no puede guiarlo. '
    'Nota: las especialidades sin procedimientos (ej. Proctology) no aparecen, '
    'porque no hay nada que ofrecer al paciente.';

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- Las cuentas de la vista deben coincidir EXACTAMENTE con las tablas
SELECT specialty_name, COUNT(*) AS en_vista
FROM v_pangi_catalog
WHERE specialty_name IN ('Dental Care','Plastic and Reconstructive Surgery')
GROUP BY specialty_name ORDER BY specialty_name;
-- Esperado: Dental Care 48 · Plastic and Reconstructive Surgery 15

-- Cero duplicados en toda la vista
SELECT specialty_name, procedure_name, COUNT(*) AS veces
FROM v_pangi_catalog
GROUP BY specialty_name, procedure_name
HAVING COUNT(*) > 1;
-- Esperado: 0 filas

-- Los dos casos que causaban la duplicación, ahora agregados
SELECT procedure_name, procedure_keys, in_kb
FROM v_pangi_catalog
WHERE specialty_name = 'Dental Care'
  AND ARRAY_LENGTH(procedure_keys, 1) > 1
ORDER BY procedure_name;
-- Esperado: 2 filas
--   Crowns and Bridges                {corona_dental,puente_dental}
--   Orthodontics (Braces, Invisalign) {ortodoncia_brackets,ortodoncia_invisible}

-- Cobertura de la KB sobre lo que Pangi ofrece
SELECT specialty_name,
       COUNT(*)                        AS ofrece_pangi,
       COUNT(*) FILTER (WHERE in_kb)   AS cubre_sage,
       COUNT(*) FILTER (WHERE NOT in_kb) AS sin_cubrir
FROM v_pangi_catalog
GROUP BY specialty_name ORDER BY specialty_name;
-- Dental Care                        48 · 12 · 36  (los 36 son la lista granular)
-- Plastic and Reconstructive Surgery 15 · 10 ·  5  (los 5 reconstructivos)
