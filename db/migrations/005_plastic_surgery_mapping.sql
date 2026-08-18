-- ============================================================
-- 005 — Mapeo de cirugía plástica al catálogo de Pangi
-- ============================================================
-- Completa lo que la migración 004 dejó en NULL a propósito.
--
-- Contexto: al momento de la 004, el catálogo de Pangi bajo
-- "Plastic and Reconstructive Surgery" solo tenía 5 procedimientos,
-- todos reconstructivos. Los 10 de esta KB son estéticos, así que
-- el solapamiento era cero y SAGE no podía crear solicitudes de
-- esta especialidad en Pangi.
--
-- El 18/08/2026 se cargaron los 10 procedimientos estéticos desde
-- admin.pangi.com, en los tres idiomas (EN/ES/PT). La especialidad
-- pasó de 5 a 15 procedimientos y allow_number_of_procedure subió
-- de 1 a 3 (permite combinar, ej. liposucción + BBL).
--
-- ⚠️ Los strings vienen del API verificado, NO escribirlos a mano.
--    El campo category del post-treatment sigue siendo el nombre
--    EN INGLÉS ("Plastic and Reconstructive Surgery"), aunque el
--    admin ahora tenga name_es y name_pt cargados.
--
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero | Agosto 2026
-- ============================================================

BEGIN;

UPDATE knowledge_base SET pangi_procedure_name = 'Rhinoplasty'
    WHERE procedure_key = 'rinoplastia';
UPDATE knowledge_base SET pangi_procedure_name = 'Liposuction'
    WHERE procedure_key = 'liposuccion';
UPDATE knowledge_base SET pangi_procedure_name = 'Breast Augmentation'
    WHERE procedure_key = 'aumento_mamario';
UPDATE knowledge_base SET pangi_procedure_name = 'Brazilian Butt Lift (BBL)'
    WHERE procedure_key = 'bbl';
UPDATE knowledge_base SET pangi_procedure_name = 'Abdominoplasty (Tummy Tuck)'
    WHERE procedure_key = 'abdominoplastia';
UPDATE knowledge_base SET pangi_procedure_name = 'Blepharoplasty (Eyelid Surgery)'
    WHERE procedure_key = 'blefaroplastia';
UPDATE knowledge_base SET pangi_procedure_name = 'Otoplasty (Ear Surgery)'
    WHERE procedure_key = 'otoplastia';
UPDATE knowledge_base SET pangi_procedure_name = 'Facelift'
    WHERE procedure_key = 'lifting_facial';
UPDATE knowledge_base SET pangi_procedure_name = 'Buccal Fat Removal'
    WHERE procedure_key = 'bichectomia';
UPDATE knowledge_base SET pangi_procedure_name = 'Breast Reduction'
    WHERE procedure_key = 'reduccion_mamaria';

COMMIT;

-- ============================================================
-- NOTAS PARA LA INTEGRACIÓN
-- ============================================================
-- 1. Los 22 procedimientos quedan mapeados. SAGE ya puede armar
--    el payload de post-treatment-concern para ambas especialidades.
--
-- 2. allow_number_of_procedure es una regla POR ESPECIALIDAD
--    (dental=3, plástica=3) y no vive en esta tabla. Se leerá
--    desde el catálogo sincronizado (workflow 06_pangi_catalog_sync),
--    no se hardcodea aquí.
--
-- 3. Los 5 procedimientos reconstructivos de Pangi (reconstrucción
--    mamaria, mano, quemaduras, labio leporino, microcirugía) NO
--    tienen equivalente en esta KB: no hay preguntas clínicas ni
--    exámenes definidos para ellos. Si un paciente los pide, SAGE
--    no puede guiarlo todavía. Fuera de alcance por ahora.
--
-- 4. Pendiente de verificar con el contacto técnico backend de Pangi: cómo Pangi rutea una solicitud
--    a los proveedores. Si lo hace por el array procedures, los 4
--    procedimientos dentales que mapean a ítems de la lista granular
--    (extracciones, limpieza profunda, prótesis) podrían no alcanzar
--    a ningún médico, porque ninguno los tiene seleccionados.
-- ============================================================

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT specialty,
       COUNT(*)                                AS total,
       COUNT(pangi_procedure_name)             AS mapeados,
       COUNT(*) - COUNT(pangi_procedure_name)  AS pendientes
FROM knowledge_base
GROUP BY specialty ORDER BY specialty;
-- Esperado: dental 12/12/0 · plastic_surgery 10/10/0

SELECT procedure_key, procedure_name, pangi_procedure_name
FROM knowledge_base
WHERE specialty = 'plastic_surgery'
ORDER BY procedure_key;

-- Ningún procedimiento sin mapear en todo el catálogo
SELECT COUNT(*) AS sin_mapear
FROM knowledge_base
WHERE pangi_procedure_name IS NULL;
-- Esperado: 0

-- Ningún nombre duplicado inesperado en cirugía plástica
-- (en dental sí hay 2 colisiones conocidas y aceptadas:
--  corona/puente → Crowns and Bridges
--  brackets/invisible → Orthodontics (Braces, Invisalign))
SELECT pangi_procedure_name, COUNT(*) AS veces
FROM knowledge_base
GROUP BY pangi_procedure_name
HAVING COUNT(*) > 1
ORDER BY pangi_procedure_name;
-- Esperado: solo las 2 colisiones dentales
