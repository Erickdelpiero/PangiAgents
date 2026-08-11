-- ============================================================
-- PANGI — Knowledge Base Migration v1.1.0
-- Migración del formato legacy de critical_questions y required_info
-- al formato paired {key, question} para eliminar el mismatch de labels.
--
-- Contexto:
--   v1.0: critical_questions = ["Q1","Q2"]  +  required_info = ["k1","k2","k3"]
--         → Arrays independientes, diferente longitud → mismatch silencioso
--
--   v1.1: critical_questions = [{"key":"k1","question":"Q1"}, ...]
--         required_info = ["k1","k2",...]  (siempre sincronizado)
--         → El código de SAGE lee las keys del mismo objeto que la pregunta
--         → Imposible que se desalineen
--
-- Filosofía de diseño:
--   - 3 a 5 preguntas por procedimiento (UX WhatsApp)
--   - Solo preguntas de alto impacto clínico para el cotizador
--   - Keys descriptivos y legibles (son los labels que ve el paciente)
--   - Los campos secundarios (medicamentos, alergias genéricas) se
--     consolidan en preguntas combinadas para reducir fricciones
--   - En V2, Claude API extraerá semánticamente todos los datos
--     de respuestas libres; estas preguntas serán la guía estructural
--
-- Alcance: 21 procedimientos (ortodoncia_invisible ya migrado en v1.0.1)
-- Autor: generado para Erick Del Piero — Sistema Pangi
-- Fecha: Marzo 2026
-- ============================================================

BEGIN;

-- ============================================================
-- ██████  ESPECIALIDAD DENTAL (11 procedimientos)
-- ============================================================

-- ── 1. BLANQUEAMIENTO DENTAL ──────────────────────────────
-- v1.0: 3 preguntas / 4 keys → mismatch (tipo_decoloracion sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "tipo_decoloracion",            "question": "¿Su discoloración es por manchas externas (café, vino, tabaco) o es decoloración interna del diente?"},
    {"key": "sensibilidad_previa",          "question": "¿Ha tenido sensibilidad dental antes?"},
    {"key": "coronas_o_carillas_existentes","question": "¿Tiene coronas, carillas o restauraciones visibles en dientes frontales?"},
    {"key": "tratamientos_previos",         "question": "¿Ha realizado blanqueamientos anteriores?"}
  ]'::jsonb,
  required_info = '["tipo_decoloracion","sensibilidad_previa","coronas_o_carillas_existentes","tratamientos_previos"]'::jsonb
WHERE procedure_key = 'blanqueamiento';

-- ── 2. CARILLAS / VENEERS ─────────────────────────────────
-- v1.0: 4 preguntas / 6 keys → mismatch (dientes_objetivo y color_deseado sin pregunta)
-- v1.1: 4 preguntas / 4 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "numero_carillas",    "question": "¿En cuántos dientes desea las carillas y en cuáles? (ej: 6 dientes superiores)"},
    {"key": "motivo_estetico",    "question": "¿Cuál es su principal objetivo estético? (color, forma, alineación, tamaño)"},
    {"key": "bruxismo",           "question": "¿Aprieta o rechina los dientes (bruxismo)?"},
    {"key": "ortodoncia_previa",  "question": "¿Tiene ortodoncia activa o finalizada recientemente?"}
  ]'::jsonb,
  required_info = '["numero_carillas","motivo_estetico","bruxismo","ortodoncia_previa"]'::jsonb
WHERE procedure_key = 'carillas_veneers';

-- ── 3. CORONA DENTAL ─────────────────────────────────────
-- v1.0: 4 preguntas / 5 keys → mismatch (motivo_corona sin pregunta, alergias_metales sin pregunta clara)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "diente_afectado",    "question": "¿En qué diente necesita la corona?"},
    {"key": "motivo_corona",      "question": "¿Por qué necesita la corona? (fractura, caries extensa, post-endodoncia, estético)"},
    {"key": "material_preferido", "question": "¿Tiene preferencia de material? (porcelana pura, zirconio, metal-porcelana)"},
    {"key": "endodoncia_previa",  "question": "¿El diente ya tiene endodoncia (tratamiento de conducto) realizada?"}
  ]'::jsonb,
  required_info = '["diente_afectado","motivo_corona","material_preferido","endodoncia_previa"]'::jsonb
WHERE procedure_key = 'corona_dental';

-- ── 4. ENDODONCIA (CONDUCTO) ──────────────────────────────
-- v1.0: 4 preguntas / 5 keys → mismatch (medicamentos sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado (medicamentos consolidado en infeccion)
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "diente_afectado",      "question": "¿En qué diente tiene el problema?"},
    {"key": "nivel_dolor",          "question": "¿Cuánto dolor tiene actualmente? (escala 1-10, siendo 10 insoportable)"},
    {"key": "infeccion_presente",   "question": "¿Tiene absceso, hinchazón o infección visible?"},
    {"key": "corona_necesaria_post","question": "¿El diente ya tiene corona o tendrá que ponerse una después del tratamiento?"}
  ]'::jsonb,
  required_info = '["diente_afectado","nivel_dolor","infeccion_presente","corona_necesaria_post"]'::jsonb
WHERE procedure_key = 'endodoncia';

-- ── 5. EXTRACCIÓN MUELA DEL JUICIO ───────────────────────
-- v1.0: 4 preguntas / 7 keys → mismatch severo (3 keys sin pregunta)
-- v1.1: 4 preguntas / 4 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "numero_muelas_afectadas",  "question": "¿Cuántas muelas del juicio necesita extraer?"},
    {"key": "posicion_muela",           "question": "¿Las muelas están impactadas (enterradas/torcidas) o tienen salida normal?"},
    {"key": "dolor_e_infeccion_actual", "question": "¿Tiene dolor, hinchazón o infección actualmente?"},
    {"key": "medicamentos_y_alergias",  "question": "¿Toma anticoagulantes o tiene alguna alergia a medicamentos relevante?"}
  ]'::jsonb,
  required_info = '["numero_muelas_afectadas","posicion_muela","dolor_e_infeccion_actual","medicamentos_y_alergias"]'::jsonb
WHERE procedure_key = 'extraccion_muela_juicio';

-- ── 6. EXTRACCIÓN SIMPLE ──────────────────────────────────
-- v1.0: 3 preguntas / 5 keys → mismatch (medicamentos_actuales y alergias sin pregunta separada)
-- v1.1: 3 preguntas / 3 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "diente_afectado",          "question": "¿Cuál diente necesita extracción? (ej: molar superior derecho, incisivo)"},
    {"key": "dolor_e_infeccion_actual", "question": "¿Tiene dolor o infección actualmente?"},
    {"key": "medicamentos_y_condiciones","question": "¿Toma anticoagulantes, tiene diabetes u otras condiciones médicas relevantes?"}
  ]'::jsonb,
  required_info = '["diente_afectado","dolor_e_infeccion_actual","medicamentos_y_condiciones"]'::jsonb
WHERE procedure_key = 'extraccion_simple';

-- ── 7. IMPLANTE DENTAL ────────────────────────────────────
-- v1.0: 5 preguntas / 7 keys → mismatch (medicamentos y fecha_ultima_extraccion sin pregunta)
-- v1.1: 5 preguntas / 5 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "numero_implantes",    "question": "¿Cuántos implantes necesita?"},
    {"key": "zona_boca",           "question": "¿En qué zona? (superior/inferior, frontal/posterior, lado derecho/izquierdo)"},
    {"key": "densidad_osea",       "question": "¿Tiene diagnóstico de densidad ósea o tomografía dental reciente?"},
    {"key": "condiciones_medicas", "question": "¿Tiene diabetes, osteoporosis o toma bifosfonatos?"},
    {"key": "fumador",             "question": "¿Es fumador/a? (afecta significativamente la integración del implante)"}
  ]'::jsonb,
  required_info = '["numero_implantes","zona_boca","densidad_osea","condiciones_medicas","fumador"]'::jsonb
WHERE procedure_key = 'implante_dental';

-- ── 8. LIMPIEZA PROFUNDA (PERIODONCIA) ───────────────────
-- v1.0: 4 preguntas / 6 keys → mismatch (nivel_sarro sin pregunta, diabetes/tabaquismo combinados)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "sangrado_encias",                    "question": "¿Le sangran las encías con frecuencia al cepillarse?"},
    {"key": "bolsas_periodontales_diagnosticadas","question": "¿Le han diagnosticado periodontitis o bolsas periodontales?"},
    {"key": "ultima_limpieza",                    "question": "¿Cuándo fue su última limpieza dental?"},
    {"key": "factores_riesgo",                    "question": "¿Es fumador/a o tiene diabetes?"}
  ]'::jsonb,
  required_info = '["sangrado_encias","bolsas_periodontales_diagnosticadas","ultima_limpieza","factores_riesgo"]'::jsonb
WHERE procedure_key = 'limpieza_profunda';

-- ── 9. ORTODONCIA BRACKETS ───────────────────────────────
-- v1.0: 3 preguntas / 5 keys → mismatch (edad y bruxismo sin pregunta)
-- v1.1: 3 preguntas / 3 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "tratamiento_previo",   "question": "¿Ha tenido ortodoncia anteriormente?"},
    {"key": "tipo_malocusion",      "question": "¿Cuál es su principal preocupación? (apiñamiento, mordida abierta, mordida cruzada, estética)"},
    {"key": "extracciones_previas", "question": "¿Le han extraído dientes para ortodoncia anteriormente?"}
  ]'::jsonb,
  required_info = '["tratamiento_previo","tipo_malocusion","extracciones_previas"]'::jsonb
WHERE procedure_key = 'ortodoncia_brackets';

-- ── 10. PRÓTESIS DENTAL COMPLETA ─────────────────────────
-- v1.0: 3 preguntas / 5 keys → mismatch (estado_encias y alergias_materiales sin pregunta)
-- v1.1: 3 preguntas / 3 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "tipo_protesis",         "question": "¿Necesita prótesis superior, inferior o ambas?"},
    {"key": "dientes_restantes",     "question": "¿Le quedan dientes propios o necesita extracciones previas a la prótesis?"},
    {"key": "uso_protesis_anterior", "question": "¿Ha usado prótesis antes? Si es así, ¿qué problemas tuvo?"}
  ]'::jsonb,
  required_info = '["tipo_protesis","dientes_restantes","uso_protesis_anterior"]'::jsonb
WHERE procedure_key = 'protesis_completa';

-- ── 11. PUENTE DENTAL ────────────────────────────────────
-- v1.0: 4 preguntas / 5 keys → mismatch (condicion_encias sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "dientes_ausentes",   "question": "¿Cuántos dientes le faltan y en qué zona? (ej: 2 molares inferiores izquierdos)"},
    {"key": "dientes_pilares",    "question": "¿Los dientes vecinos al espacio están sanos? (serán los pilares del puente)"},
    {"key": "material_preferido", "question": "¿Tiene preferencia de material? (porcelana, zirconio, metal-porcelana)"},
    {"key": "tiempo_ausencia",    "question": "¿Cuánto tiempo lleva sin esos dientes?"}
  ]'::jsonb,
  required_info = '["dientes_ausentes","dientes_pilares","material_preferido","tiempo_ausencia"]'::jsonb
WHERE procedure_key = 'puente_dental';


-- ============================================================
-- ██████  ESPECIALIDAD CIRUGÍA PLÁSTICA (10 procedimientos)
-- ============================================================

-- ── 12. ABDOMINOPLASTIA ──────────────────────────────────
-- v1.0: 5 preguntas / 7 keys → mismatch (condiciones_medicas y planes_embarazo_futuro sin pregunta clara)
-- v1.1: 5 preguntas / 5 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "imc_actual",             "question": "¿Cuál es su IMC aproximado, o cuánto pesa y cuánto mide?"},
    {"key": "perdida_peso_reciente",  "question": "¿Ha tenido pérdida de peso significativa recientemente?"},
    {"key": "embarazos_y_planes",     "question": "¿Ha tenido embarazos? ¿Planea embarazarse en el futuro?"},
    {"key": "cicatrices_abdominales", "question": "¿Tiene cicatrices abdominales previas? (cesárea, apendicitis, otras cirugías)"},
    {"key": "fumador",                "question": "¿Es fumador/a? (el tabaco afecta crítica mente la cicatrización)"}
  ]'::jsonb,
  required_info = '["imc_actual","perdida_peso_reciente","embarazos_y_planes","cicatrices_abdominales","fumador"]'::jsonb
WHERE procedure_key = 'abdominoplastia';

-- ── 13. AUMENTO DE BUSTO ─────────────────────────────────
-- v1.0: 5 preguntas / 7 keys → mismatch (tipo_implante_preferido y posicion_implante sin pregunta)
-- v1.1: 5 preguntas / 5 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "talla_actual",             "question": "¿Cuál es su talla actual de busto?"},
    {"key": "resultado_deseado",        "question": "¿Qué resultado desea lograr? (natural, notorio, talla aproximada)"},
    {"key": "lactancia_futura",         "question": "¿Planea amamantar en el futuro?"},
    {"key": "mamografia_previa",        "question": "¿Ha tenido mamografía reciente? (importante si tiene más de 35 años)"},
    {"key": "antecedentes_cancer_mama", "question": "¿Tiene antecedentes personales o familiares de cáncer de mama?"}
  ]'::jsonb,
  required_info = '["talla_actual","resultado_deseado","lactancia_futura","mamografia_previa","antecedentes_cancer_mama"]'::jsonb
WHERE procedure_key = 'aumento_mamario';

-- ── 14. BBL (BRAZILIAN BUTT LIFT) ────────────────────────
-- v1.0: 5 preguntas / 7 keys → mismatch (resultado_deseado y medicamentos sin pregunta)
-- v1.1: 5 preguntas / 5 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "imc_actual",             "question": "¿Cuál es su IMC aproximado? (el BBL requiere suficiente grasa para transferir)"},
    {"key": "peso_estable",           "question": "¿Su peso ha sido estable los últimos 6 meses?"},
    {"key": "zona_donante_grasa",     "question": "¿Tiene zonas con grasa disponible? (abdomen, flancos, muslos, espalda)"},
    {"key": "resultado_deseado",      "question": "¿Qué resultado desea lograr con el BBL? (proyección, forma, volumen)"},
    {"key": "condiciones_coagulacion","question": "¿Es fumador/a o tiene condiciones de coagulación?"}
  ]'::jsonb,
  required_info = '["imc_actual","peso_estable","zona_donante_grasa","resultado_deseado","condiciones_coagulacion"]'::jsonb
WHERE procedure_key = 'bbl';

-- ── 15. BICHECTOMÍA ──────────────────────────────────────
-- v1.0: 3 preguntas / 5 keys → mismatch (motivo_estetico e imc_actual sin pregunta clara)
-- v1.1: 3 preguntas / 3 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "expectativas_resultado",        "question": "¿Cuál es su objetivo con la bichectomía? (rostro más definido, pómulos marcados, adelgazar la cara)"},
    {"key": "peso_estable",                  "question": "¿Su peso ha sido estable en los últimos meses?"},
    {"key": "otros_procedimientos_faciales", "question": "¿Tiene otros procedimientos faciales en mente? (rinoplastia, bótox, etc.)"}
  ]'::jsonb,
  required_info = '["expectativas_resultado","peso_estable","otros_procedimientos_faciales"]'::jsonb
WHERE procedure_key = 'bichectomia';

-- ── 16. BLEFAROPLASTIA (PÁRPADOS) ────────────────────────
-- v1.0: 4 preguntas / 6 keys → mismatch (edad y examenes_oftalmologicos sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "parpados_afectados",         "question": "¿Desea corregir párpados superiores, inferiores o ambos?"},
    {"key": "motivo_funcional_estetico",  "question": "¿Es un problema funcional (visión afectada por el párpado) o principalmente estético?"},
    {"key": "condiciones_oculares",       "question": "¿Tiene condiciones oculares como glaucoma, ojo seco o usa lentes de contacto?"},
    {"key": "medicamentos_anticoagulantes","question": "¿Toma anticoagulantes, aspirina o medicamentos que afecten la coagulación?"}
  ]'::jsonb,
  required_info = '["parpados_afectados","motivo_funcional_estetico","condiciones_oculares","medicamentos_anticoagulantes"]'::jsonb
WHERE procedure_key = 'blefaroplastia';

-- ── 17. LIFTING FACIAL ───────────────────────────────────
-- v1.0: 4 preguntas / 6 keys → mismatch (edad y condiciones_medicas sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "areas_objetivo",              "question": "¿Qué áreas le preocupan principalmente? (mejillas, cuello, mandíbula, todo el rostro)"},
    {"key": "procedimientos_previos",      "question": "¿Ha tenido procedimientos estéticos faciales anteriores? (rellenos, bótox, cirugías)"},
    {"key": "fumador",                     "question": "¿Es fumador/a? (factor crítico: el tabaco puede comprometer la cicatrización)"},
    {"key": "medicamentos_anticoagulantes","question": "¿Toma anticoagulantes o medicamentos que puedan afectar la coagulación?"}
  ]'::jsonb,
  required_info = '["areas_objetivo","procedimientos_previos","fumador","medicamentos_anticoagulantes"]'::jsonb
WHERE procedure_key = 'lifting_facial';

-- ── 18. LIPOSUCCIÓN ──────────────────────────────────────
-- v1.0: 4 preguntas / 7 keys → mismatch (imc_actual, expectativas y medicamentos sin pregunta)
-- v1.1: 4 preguntas / 4 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "zonas_objetivo",  "question": "¿En qué zonas desea la liposucción? (abdomen, flancos, muslos, brazos, papada, etc.)"},
    {"key": "peso_estable",    "question": "¿Su peso ha sido estable los últimos 6 meses?"},
    {"key": "expectativas",    "question": "¿Cuál es su objetivo principal? (definición muscular, reducción de volumen, contorno corporal)"},
    {"key": "factores_riesgo", "question": "¿Es fumador/a o tiene condiciones médicas relevantes como diabetes o problemas de coagulación?"}
  ]'::jsonb,
  required_info = '["zonas_objetivo","peso_estable","expectativas","factores_riesgo"]'::jsonb
WHERE procedure_key = 'liposuccion';

-- ── 19. OTOPLASTIA (OREJAS) ──────────────────────────────
-- v1.0: 3 preguntas / 4 keys → mismatch (expectativas sin pregunta)
-- v1.1: 3 preguntas / 3 keys → consolidado, alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "tipo_problema",    "question": "¿Cuál es el problema a corregir? (orejas prominentes/separadas, asimetría, forma del cartílago)"},
    {"key": "edad_paciente",    "question": "¿Es para usted o para un menor de edad?"},
    {"key": "lado_afectado",    "question": "¿Están afectadas una o ambas orejas?"}
  ]'::jsonb,
  required_info = '["tipo_problema","edad_paciente","lado_afectado"]'::jsonb
WHERE procedure_key = 'otoplastia';

-- ── 20. REDUCCIÓN DE BUSTO ───────────────────────────────
-- v1.0: 4 preguntas / 6 keys → mismatch (actividad_fisica_limitada y condiciones_medicas sin pregunta)
-- v1.1: 4 preguntas / 4 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "talla_actual",      "question": "¿Cuál es su talla actual de busto?"},
    {"key": "sintomas_fisicos",  "question": "¿Tiene dolor de espalda, cuello, hombros o rozaduras relacionadas al tamaño del busto?"},
    {"key": "resultado_deseado", "question": "¿Qué resultado desea lograr? (talla aproximada deseada)"},
    {"key": "mamografia_previa", "question": "¿Ha tenido mamografía reciente?"}
  ]'::jsonb,
  required_info = '["talla_actual","sintomas_fisicos","resultado_deseado","mamografia_previa"]'::jsonb
WHERE procedure_key = 'reduccion_mamaria';

-- ── 21. RINOPLASTIA ──────────────────────────────────────
-- v1.0: 5 preguntas / 7 keys → mismatch (medicamentos e imc sin pregunta)
-- v1.1: 5 preguntas / 5 keys → alineado
UPDATE knowledge_base SET
  critical_questions = '[
    {"key": "motivo_funcional_estetico", "question": "¿Su objetivo es estético, funcional (mejorar la respiración) o ambos?"},
    {"key": "cirugias_nasales_previas",  "question": "¿Ha tenido cirugías nasales previas?"},
    {"key": "problemas_respiratorios",   "question": "¿Tiene problemas de respiración nasal actualmente?"},
    {"key": "expectativas_resultado",    "question": "¿Puede describir qué cambio desea ver? (referentes visuales son bienvenidos)"},
    {"key": "fumador",                   "question": "¿Es fumador/a?"}
  ]'::jsonb,
  required_info = '["motivo_funcional_estetico","cirugias_nasales_previas","problemas_respiratorios","expectativas_resultado","fumador"]'::jsonb
WHERE procedure_key = 'rinoplastia';


-- ============================================================
-- VERIFICACIÓN POST-MIGRACIÓN
-- Ejecutar después del COMMIT para confirmar que todo está alineado.
-- Todos los registros deben mostrar: arrays_aligned = true, questions_format = object
-- ============================================================
COMMIT;

-- ── Query de verificación (ejecutar separado del bloque de transacción)
SELECT
  procedure_key,
  specialty,
  jsonb_array_length(critical_questions) AS num_questions,
  jsonb_array_length(required_info)      AS num_keys,
  jsonb_array_length(critical_questions) = jsonb_array_length(required_info) AS arrays_aligned,
  jsonb_typeof(critical_questions->0)    AS questions_format
FROM knowledge_base
WHERE is_active = TRUE
ORDER BY specialty, procedure_key;
