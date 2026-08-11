-- ============================================================
-- PANGI_DEV  Schema v1.0.0
-- Sistema NOVA · SAGE · ATLAS  +  WhatsApp
-- Autor: Erick Del Piero  |  Marzo 2026
-- ============================================================

-- 1. USUARIOS — identificados por número de teléfono WhatsApp
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    phone           VARCHAR(30) UNIQUE NOT NULL,
    name            VARCHAR(100),
    language        VARCHAR(5) DEFAULT 'es',
    first_contact   TIMESTAMPTZ DEFAULT NOW(),
    last_activity   TIMESTAMPTZ DEFAULT NOW(),
    is_active       BOOLEAN DEFAULT TRUE,
    metadata        JSONB DEFAULT '{}'
);

-- 2. SESSIONS — estado activo de la conversación por usuario
CREATE TABLE sessions (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id) ON DELETE CASCADE,
    active_agent    VARCHAR(10) NOT NULL DEFAULT 'NOVA',
    state           VARCHAR(50) DEFAULT 'initial',
    context         JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    expires_at      TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours'
);

-- 3. CONVERSATION_HISTORY — historial completo persistente
CREATE TABLE conversation_history (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id      INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    agent           VARCHAR(10) NOT NULL,
    role            VARCHAR(10) NOT NULL,
    message         TEXT NOT NULL,
    message_type    VARCHAR(20) DEFAULT 'text',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 4. MEDICAL_INTAKE — datos recopilados por SAGE en el chat
--    NOTA: Solo datos que el usuario comparte voluntariamente.
--    Los datos clínicos de Pangi se leen en producción pero NUNCA se escriben aquí.
CREATE TABLE medical_intake (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id          INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    specialty           VARCHAR(50) NOT NULL,
    procedure_name      VARCHAR(100),
    collected_data      JSONB DEFAULT '{}',
    missing_items       JSONB DEFAULT '[]',
    completeness_score  INTEGER DEFAULT 0,
    status              VARCHAR(20) DEFAULT 'in_progress',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 5. QUOTES_COMPARISON — cotizaciones recibidas para que ATLAS compare
CREATE TABLE quotes_comparison (
    id                      SERIAL PRIMARY KEY,
    user_id                 INTEGER REFERENCES users(id) ON DELETE CASCADE,
    intake_id               INTEGER REFERENCES medical_intake(id) ON DELETE SET NULL,
    destination_city        VARCHAR(100),
    destination_country     VARCHAR(100),
    procedure_cost          NUMERIC(10,2),
    doctor_name             VARCHAR(100),
    clinic_name             VARCHAR(100),
    doctor_experience_years INTEGER,
    additional_notes        TEXT,
    quote_data              JSONB DEFAULT '{}',
    created_at              TIMESTAMPTZ DEFAULT NOW()
);

-- 6. ATLAS_DESTINATIONS — datos estáticos de destinos de turismo médico
CREATE TABLE atlas_destinations (
    id                              SERIAL PRIMARY KEY,
    country                         VARCHAR(100) NOT NULL,
    city                            VARCHAR(100) NOT NULL,
    avg_flight_cost_usd             NUMERIC(8,2),
    avg_hotel_cost_per_night_usd    NUMERIC(8,2),
    avg_recovery_days_dental        INTEGER DEFAULT 3,
    avg_recovery_days_plastic       INTEGER DEFAULT 7,
    climate_type                    VARCHAR(50),
    languages                       VARCHAR(100) DEFAULT 'español',
    visa_required_us                BOOLEAN DEFAULT FALSE,
    notes                           TEXT,
    is_active                       BOOLEAN DEFAULT TRUE
);

-- 7. KNOWLEDGE_BASE — procedimientos y requisitos por especialidad (SAGE)
CREATE TABLE knowledge_base (
    id                  SERIAL PRIMARY KEY,
    specialty           VARCHAR(50) NOT NULL,
    procedure_name      VARCHAR(100) NOT NULL,
    procedure_key       VARCHAR(100) UNIQUE NOT NULL,
    required_info       JSONB NOT NULL,
    critical_questions  JSONB NOT NULL,
    required_exams      JSONB DEFAULT '[]',
    typical_recovery_days INTEGER,
    sage_intro_message  TEXT,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 8. AGENT_HANDOFFS — log de transferencias entre agentes
CREATE TABLE agent_handoffs (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id          INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    from_agent          VARCHAR(10) NOT NULL,
    to_agent            VARCHAR(10) NOT NULL,
    reason              VARCHAR(200),
    context_snapshot    JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES — para performance en consultas frecuentes
-- ============================================================
CREATE INDEX idx_users_phone           ON users(phone);
CREATE INDEX idx_users_last_activity   ON users(last_activity);
CREATE INDEX idx_sessions_user_id      ON sessions(user_id);
CREATE INDEX idx_sessions_expires      ON sessions(expires_at);
CREATE INDEX idx_sessions_agent        ON sessions(active_agent);
CREATE INDEX idx_conv_user_id          ON conversation_history(user_id);
CREATE INDEX idx_conv_session_id       ON conversation_history(session_id);
CREATE INDEX idx_conv_created          ON conversation_history(created_at);
CREATE INDEX idx_intake_user           ON medical_intake(user_id);
CREATE INDEX idx_intake_specialty      ON medical_intake(specialty);
CREATE INDEX idx_kb_key                ON knowledge_base(procedure_key);
CREATE INDEX idx_kb_specialty          ON knowledge_base(specialty);

-- ============================================================
-- TRIGGERS — auto-actualización de updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sessions_updated_at
    BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_intake_updated_at
    BEFORE UPDATE ON medical_intake
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- FUNCTION — cleanup de sesiones expiradas
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    UPDATE sessions SET state = 'expired'
    WHERE expires_at < NOW() AND state != 'expired';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SEED: ATLAS_DESTINATIONS (10 destinos con datos estáticos)
-- ============================================================
INSERT INTO atlas_destinations
    (country, city, avg_flight_cost_usd, avg_hotel_cost_per_night_usd,
     avg_recovery_days_dental, avg_recovery_days_plastic,
     climate_type, languages, visa_required_us, notes)
VALUES
('México',              'Ciudad de México', 350, 80,  2, 7,  'templado',    'español',          FALSE, 'Gran hub médico, alta disponibilidad de especialistas'),
('México',              'Cancún',           280, 120, 2, 7,  'tropical',    'español, inglés',  FALSE, 'Turismo médico + playa, muy popular para pacientes de EE.UU.'),
('Colombia',            'Bogotá',           420, 70,  2, 7,  'templado',    'español',          FALSE, 'Capital médica de Colombia, excelente infraestructura hospitalaria'),
('Colombia',            'Medellín',         400, 65,  2, 7,  'templado',    'español',          FALSE, 'Ciudad de la eterna primavera, reconocida mundialmente por cirugía plástica'),
('Colombia',            'Cartagena',        450, 90,  2, 7,  'tropical',    'español',          FALSE, 'Recuperación en ciudad colonial caribeña, muy recomendada para turismo médico'),
('Perú',                'Lima',             500, 75,  2, 7,  'templado',    'español',          FALSE, 'Creciente hub médico con precios muy competitivos'),
('Costa Rica',          'San José',         380, 80,  2, 7,  'tropical',    'español, inglés',  FALSE, 'Alta calidad médica, destino favorito de estadounidenses desde los 90s'),
('Argentina',           'Buenos Aires',     650, 60,  2, 7,  'templado',    'español',          FALSE, 'Excelente calidad médica, precios muy competitivos post-devaluación'),
('República Dominicana','Santo Domingo',    300, 85,  2, 7,  'tropical',    'español, inglés',  FALSE, 'Cercanía a EE.UU., combina turismo médico con resort'),
('USA',                 'Miami',            0,   180, 2, 7,  'subtropical', 'inglés, español',  FALSE, 'Precio de referencia local — base de comparación para el análisis de ATLAS');

-- ============================================================
-- SEED: KNOWLEDGE_BASE — ESPECIALIDAD DENTAL (12 procedimientos)
-- ============================================================
INSERT INTO knowledge_base
    (specialty, procedure_name, procedure_key, required_info, critical_questions, required_exams, typical_recovery_days, sage_intro_message)
VALUES

('dental', 'Extracción Simple', 'extraccion_simple',
 '["diente_afectado","dolor_actual","infeccion_presente","medicamentos_actuales","alergias"]',
 '["¿Cuál diente necesita extracción?","¿Tiene dolor o infección actualmente?","¿Toma anticoagulantes o tiene condiciones médicas relevantes?"]',
 '["radiografia_periapical"]', 1,
 'Entendido, te ayudaré a preparar tu solicitud para extracción dental. Necesito hacerte unas preguntas para que el médico pueda darte una cotización precisa 🦷'),

('dental', 'Extracción Muela del Juicio', 'extraccion_muela_juicio',
 '["numero_muelas_afectadas","posicion_muela","dolor_actual","infeccion","edad_paciente","medicamentos","alergias"]',
 '["¿Cuántas muelas del juicio necesita extraer?","¿Tiene radiografía panorámica reciente?","¿Las muelas están impactadas o tienen salida normal?","¿Tiene dolor o infección actualmente?"]',
 '["radiografia_panoramica"]', 3,
 'Vamos a preparar tu solicitud para extracción de muela(s) del juicio. Con la información correcta podrás recibir cotizaciones muy precisas 🦷'),

('dental', 'Implante Dental', 'implante_dental',
 '["numero_implantes","zona_boca","densidad_osea","diabetes_osteoporosis","fumador","medicamentos","fecha_ultima_extraccion"]',
 '["¿Cuántos implantes necesita?","¿En qué zona? (superior/inferior, frontal/posterior)","¿Tiene diagnóstico de densidad ósea suficiente?","¿Es fumador/a?","¿Tiene diabetes o toma bifosfonatos?"]',
 '["radiografia_panoramica","tomografia_cone_beam_si_disponible"]', 90,
 'Los implantes dentales son una inversión importante. Para que recibas cotizaciones precisas necesito recopilar información clave 🦷'),

('dental', 'Prótesis Dental Completa', 'protesis_completa',
 '["tipo_protesis","dientes_restantes","estado_encias","uso_protesis_anterior","alergias_materiales"]',
 '["¿Necesita prótesis superior, inferior o ambas?","¿Le quedan dientes propios o necesita extracciones previas?","¿Ha usado prótesis antes?"]',
 '["radiografia_panoramica","fotografias_boca"]', 14,
 'Preparemos tu solicitud para prótesis dental. Tengo algunas preguntas para asegurar que la cotización sea lo más precisa posible 🦷'),

('dental', 'Carillas / Veneers', 'carillas_veneers',
 '["numero_carillas","dientes_objetivo","motivo_estetico","color_deseado","bruxismo","ortodoncia_previa"]',
 '["¿En cuántos dientes desea las carillas?","¿Cuál es su principal objetivo estético? (color, forma, alineación)","¿Aprieta los dientes (bruxismo)?","¿Tiene ortodoncia activa o reciente?"]',
 '["fotografias_sonrisa_frente_perfil","radiografia_panoramica"]', 7,
 'Las carillas son una transformación estética increíble. Déjame recopilar la información que el especialista necesitará para cotizarte con precisión ✨🦷'),

('dental', 'Ortodoncia Brackets', 'ortodoncia_brackets',
 '["edad","tipo_malocusion","tratamiento_previo","extracciones_previas","bruxismo"]',
 '["¿Ha tenido ortodoncia anteriormente?","¿Cuál es su principal preocupación? (apiñamiento, mordida, estética)","¿Le han extraído dientes para ortodoncia antes?"]',
 '["radiografia_panoramica","radiografia_lateral_craneo","fotografias_frente_perfil_sonrisa"]', 548,
 'Vamos a preparar tu consulta de ortodoncia. Podemos adelantar mucha información valiosa para el especialista 🦷'),

('dental', 'Ortodoncia Invisible (Alineadores)', 'ortodoncia_invisible',
 '["edad","severidad_caso","tratamiento_previo","disponibilidad_seguimiento","presupuesto_aproximado"]',
 '["¿Ha tenido ortodoncia anteriormente?","¿Su caso es leve, moderado o severo (si lo sabe)?","¿Puede comprometerse con visitas de seguimiento cada 6-8 semanas?"]',
 '["radiografia_panoramica","fotografias_frente_perfil_sonrisa","scanner_dental_si_disponible"]', 365,
 'Los alineadores invisibles son muy populares. Déjame preguntar para que el especialista evalúe si eres candidato ideal ✨'),

('dental', 'Endodoncia (Tratamiento de Conducto)', 'endodoncia',
 '["diente_afectado","nivel_dolor","infeccion_presente","corona_necesaria_post","medicamentos"]',
 '["¿En qué diente tiene el problema?","¿Cuánto dolor tiene actualmente? (escala 1-10)","¿Tiene absceso o infección visible?","¿El diente ya tiene corona o necesitará una después?"]',
 '["radiografia_periapical"]', 3,
 'Vamos a preparar tu solicitud de endodoncia. Con la información correcta podrás cotizar con varios especialistas 🦷'),

('dental', 'Corona Dental', 'corona_dental',
 '["diente_afectado","material_preferido","motivo_corona","endodoncia_previa","alergias_metales"]',
 '["¿En qué diente necesita la corona?","¿Tiene preferencia de material? (porcelana, zirconio, metal-porcelana)","¿El diente ya tiene endodoncia realizada?","¿Tiene alergia a metales?"]',
 '["radiografia_periapical"]', 7,
 'Preparemos tu solicitud para corona dental. El material y la condición del diente son clave para una cotización precisa 🦷'),

('dental', 'Limpieza Dental Profunda (Periodoncia)', 'limpieza_profunda',
 '["nivel_sarro","sangrado_encias","bolsas_periodontales_diagnosticadas","diabetes","tabaquismo","ultima_limpieza"]',
 '["¿Le sangran las encías con frecuencia?","¿Le han diagnosticado periodontitis o bolsas periodontales?","¿Cuándo fue su última limpieza dental?","¿Es fumador/a o tiene diabetes?"]',
 '["radiografia_panoramica_si_hay_diagnostico_periodontal"]', 2,
 'La salud periodontal es la base de todo. Cuéntame un poco más para preparar la mejor solicitud 🦷'),

('dental', 'Blanqueamiento Dental', 'blanqueamiento',
 '["tipo_decoloracion","sensibilidad_previa","tratamientos_blanqueamiento_previos","coronas_o_carillas_existentes"]',
 '["¿Ha tenido sensibilidad dental antes?","¿Tiene coronas, carillas o restauraciones visibles en dientes frontales?","¿Ha realizado blanqueamientos anteriores?"]',
 '["fotografias_sonrisa"]', 1,
 '¡Una sonrisa más brillante te espera! Déjame preparar tu solicitud de blanqueamiento dental ✨'),

('dental', 'Puente Dental', 'puente_dental',
 '["dientes_ausentes","dientes_pilares","material_preferido","tiempo_ausencia","condicion_encias"]',
 '["¿Cuántos dientes le faltan y en qué zona?","¿Los dientes vecinos están sanos (serán los pilares)?","¿Tiene preferencia de material?","¿Cuánto tiempo lleva sin esos dientes?"]',
 '["radiografia_panoramica"]', 7,
 'El puente dental es una excelente solución para dientes faltantes. Preparemos tu solicitud 🦷');

-- ============================================================
-- SEED: KNOWLEDGE_BASE — CIRUGÍA PLÁSTICA (10 procedimientos)
-- ============================================================
INSERT INTO knowledge_base
    (specialty, procedure_name, procedure_key, required_info, critical_questions, required_exams, typical_recovery_days, sage_intro_message)
VALUES

('plastic_surgery', 'Rinoplastia', 'rinoplastia',
 '["motivo_funcional_estetico","cirugias_nasales_previas","problemas_respiratorios","expectativas_resultado","fumador","medicamentos","imc"]',
 '["¿Su objetivo es estético, funcional (respiración) o ambos?","¿Ha tenido cirugías nasales previas?","¿Tiene problemas de respiración nasal actualmente?","¿Puede describir qué cambio desea ver?","¿Es fumador/a?"]',
 '["fotografias_frente_perfil_3cuartos_nariz","examen_medico_general"]', 14,
 'La rinoplastia es una de las cirugías más personalizadas que existen. Necesito hacerte algunas preguntas para que el cirujano pueda darte una evaluación precisa 👃'),

('plastic_surgery', 'Abdominoplastia', 'abdominoplastia',
 '["perdida_peso_reciente","embarazos_previos","imc_actual","planes_embarazo_futuro","cicatrices_abdominales","condiciones_medicas","fumador"]',
 '["¿Cuál es su IMC aproximado?","¿Ha tenido embarazos? ¿Planea embarazarse en el futuro?","¿Ha tenido pérdida de peso significativa recientemente?","¿Tiene cicatrices abdominales previas?","¿Es fumador/a?"]',
 '["examen_medico_general","fotografias_abdomen_frente_perfil_3cuartos","examenes_preoperatorios_si_disponibles"]', 21,
 'La abdominoplastia puede transformar tu confianza. Cuéntame más para preparar una solicitud completa 💪'),

('plastic_surgery', 'Liposucción', 'liposuccion',
 '["zonas_objetivo","imc_actual","peso_estable","expectativas","condiciones_medicas","medicamentos","fumador"]',
 '["¿En qué zonas desea la liposucción? (abdomen, flancos, muslos, brazos, etc.)","¿Su peso ha sido estable los últimos 6 meses?","¿Tiene condiciones médicas relevantes?","¿Es fumador/a?"]',
 '["fotografias_zonas_objetivo","examen_medico_general"]', 14,
 'La liposucción es efectiva cuando se tiene un peso estable. Preparemos tu consulta con la información que el cirujano necesita 💪'),

('plastic_surgery', 'Aumento de Busto', 'aumento_mamario',
 '["talla_actual","resultado_deseado","tipo_implante_preferido","posicion_implante","lactancia_futura","condiciones_mama","mamografia_previa"]',
 '["¿Cuál es su talla actual de busto?","¿Qué resultado desea lograr?","¿Ha tenido mamografía reciente? (especialmente si tiene más de 35 años)","¿Planea amamantar en el futuro?","¿Tiene antecedentes familiares de cáncer de mama?"]',
 '["fotografias_frente_perfil_3cuartos_torso","mamografia_si_mayor_35","examen_medico_general"]', 14,
 'El aumento de busto es una decisión muy personal. Déjame recopilar la información que te ayudará a recibir cotizaciones precisas 🌸'),

('plastic_surgery', 'Reducción de Busto', 'reduccion_mamaria',
 '["talla_actual","resultado_deseado","dolor_espalda_presente","actividad_fisica_limitada","mamografia_previa","condiciones_medicas"]',
 '["¿Cuál es su talla actual?","¿Tiene dolor de espalda o cuello relacionado?","¿Ha tenido mamografía reciente?","¿Qué resultado desea lograr?"]',
 '["fotografias_frente_perfil_3cuartos_torso","mamografia_reciente","examen_medico_general"]', 21,
 'La reducción de busto mejora significativamente la calidad de vida. Preparemos tu consulta 🌸'),

('plastic_surgery', 'Bichectomía', 'bichectomia',
 '["motivo_estetico","imc_actual","peso_estable","expectativas_resultado","otros_procedimientos_faciales"]',
 '["¿Cuál es su objetivo con la bichectomía?","¿Su peso ha sido estable?","¿Tiene otros procedimientos faciales en mente?"]',
 '["fotografias_frente_perfil_3cuartos_rostro"]', 7,
 'La bichectomía puede definir mucho el contorno facial. Cuéntame más para preparar tu consulta ✨'),

('plastic_surgery', 'Blefaroplastia (Párpados)', 'blefaroplastia',
 '["parpados_afectados","motivo_funcional_estetico","edad","condiciones_oculares","medicamentos","examenes_oftalmologicos"]',
 '["¿Desea corregir párpados superiores, inferiores o ambos?","¿Es un problema funcional (visión afectada) o estético?","¿Tiene condiciones oculares como glaucoma o ojo seco?","¿Usa lentes de contacto?"]',
 '["fotografias_ojos_abiertos_cerrados_perfil","evaluacion_oftalmologica_si_funcional"]', 14,
 'La blefaroplastia puede rejuvenecer significativamente la mirada. Preparemos tu consulta 👁️'),

('plastic_surgery', 'Otoplastia (Orejas)', 'otoplastia',
 '["tipo_problema","edad_paciente","lado_afectado","expectativas"]',
 '["¿Cuál es el problema a corregir? (orejas prominentes, asimetría, forma)","¿Es para usted o para un menor de edad?","¿Están afectadas una o ambas orejas?"]',
 '["fotografias_frente_perfil_lateral_orejas"]', 10,
 'La otoplastia tiene un impacto enorme en la confianza. Preparemos tu consulta 👂'),

('plastic_surgery', 'Lifting Facial', 'lifting_facial',
 '["edad","areas_objetivo","procedimientos_previos","condiciones_medicas","medicamentos_anticoagulantes","fumador"]',
 '["¿Qué áreas le preocupan principalmente? (mejillas, cuello, mandíbula)","¿Ha tenido procedimientos estéticos faciales anteriores?","¿Es fumador/a? (factor crítico para cicatrización)","¿Toma anticoagulantes?"]',
 '["fotografias_frente_perfil_3cuartos_rostro","examen_medico_general"]', 21,
 'El lifting facial es una de las cirugías con mayor impacto rejuvenecedor. Preparemos tu consulta ✨'),

('plastic_surgery', 'BBL (Brazilian Butt Lift)', 'bbl',
 '["imc_actual","peso_estable","zona_donante_grasa","resultado_deseado","condiciones_medicas","medicamentos","fumador"]',
 '["¿Cuál es su IMC aproximado? (el BBL requiere grasa suficiente para transferir)","¿Su peso ha sido estable los últimos 6 meses?","¿Tiene zonas con grasa disponible? (abdomen, flancos, muslos)","¿Es fumador/a?","¿Tiene condiciones de coagulación?"]',
 '["fotografias_cuerpo_completo_frente_perfil_posterior","examen_medico_general"]', 21,
 'El BBL combina liposucción y aumento de glúteos. La candidatura correcta es clave. Preparemos tu consulta 💪');

-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================
SELECT 'TABLAS CREADAS:' AS info;
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

SELECT 'KNOWLEDGE BASE:' AS info;
SELECT specialty, count(*) AS procedimientos FROM knowledge_base GROUP BY specialty;

SELECT 'DESTINOS ATLAS:' AS info;
SELECT country, city FROM atlas_destinations ORDER BY country, city;