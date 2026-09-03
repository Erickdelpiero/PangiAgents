# Roadmap de Integración — Agentes Pangi

**Proyecto:** NOVA · SAGE · ATLAS → plataforma Pangi
**Responsable IA:** Erick Del Piero Gonzales
**Contraparte técnica:** el contacto técnico backend de Pangi
**Infraestructura Azure:** el encargado de infraestructura Azure del lado Pangi — provisiona VMs, no es especialista en infra
**Decisor:** el CEO de Pangi
**Inicio:** lunes 17 de agosto de 2026
**Última actualización:** martes 18 de agosto de 2026
**Punto de retorno:** tag `mvp-v2-pre-pangi` en `pangi-dev`

---

## 0. Estado de partida

**Lo que ya funciona:** sistema conversacional de tres agentes sobre n8n + Claude, multilenguaje (es/en/pt), handoffs sin pérdida de contexto, KB clínica de 22 procedimientos, PHI de-identificado antes de cada llamada al LLM, demostrado al CEO de Pangi sin fallas.

**Lo que está simulado:** todo lo que toca a Pangi. SAGE "publica" cambiando un flag en su propio PostgreSQL. NOVA genera una referencia de cita aleatoria en memoria que no persiste en ningún lado. ATLAS lee una tabla que nadie llena.

**Lo que se descubrió (sesión DevTools, 15–16 ago):** contratos reales de la API de Pangi verificados contra producción. Ver Anexo A.

**Hallazgo estructural clave:** `05_db_manager` (workflow `ancJzcIbrd9T9QJB`) es un router con allowlist de 19 operaciones, y es la **única** superficie de datos del sistema. Ningún agente toca la base directamente. Integrar con Pangi significa cambiar el origen de datos de operaciones puntuales en ese workflow — **no reescribir SAGE, NOVA ni ATLAS.**

**Avance al 18 de agosto:**
- Migración `004` — identidad para widget, mapeo dental 12/12, ciudades 3/10
- Migración `005` — mapeo cirugía plástica 10/10. **Los 22 procedimientos resuelven contra Pangi.**
- Catálogo de cirugía plástica poblado en el Admin: de 5 a 15 procedimientos, en tres idiomas, `allow_number_of_procedure` 1 → 3
- El contacto técnico backend de Pangi cerró R2 y R7 · el encargado de infraestructura Azure del lado Pangi provisiona la VM el 19 de agosto
- Tags: `f1-catalog-mapping`, `f1-catalog-complete`

---

## 1. El desbloqueo que define este roadmap

Cinco endpoints de Pangi son **públicos, sin autenticación** (verificado en ventana de incógnito):

```
GET /api/common/speciality?lang=es|en|pt
GET /api/common/countries
GET /api/common/available-locations
GET /api/common/doctors?...
GET /api/common/date-slots?doctor_id=&date=&clinic_address=&patient_id=
```

Consecuencia: **catálogos reales y todo el flujo de NOVA hasta el momento de reservar son construibles desde el día 1**, sin esperar la credencial de servicio.

La credencial solo bloquea tres cosas: reservar la cita, leer el perfil del paciente, y crear la solicitud de tratamiento.

---

## 2. Decisiones ya cerradas

| Decisión | Resolución |
|---|---|
| Alcance de especialidades | Solo **dental** y **cirugía plástica**. Lo que falte de un lado se agrega del otro. Las otras 20 especialidades son responsabilidad del CEO de Pangi y no frenan la integración. |
| Persistencia | **Opción A**: PostgreSQL guarda el borrador; al confirmar, UNA llamada crea el `post_treatment` en Pangi y se guarda el `_id` de vuelta. |
| Campo clínico | `medical_description` (ya existe). **No se pide `clinical_intake`** — evita tocar el esquema core de Pangi. Se evalúa en fase 2. |
| Hosting | Una VM en el Azure de Pangi (n8n + LiteLLM) + PostgreSQL gestionado. Si al encargado de infraestructura Azure del lado Pangi le resulta más simple, Postgres puede ir en la VM y se migra después. |
| Dimensionamiento | **8 GB ahora**, sube a **16 GB antes de producción** para autohospedar Langfuse. Redimensionar en Azure es un reinicio, no una migración. |
| Observabilidad | **Langfuse Cloud (gratis) es temporal.** Ver R8 — tiene condición de salida obligatoria. |
| Sincronización de catálogo | **Enfoque dual.** Ahora: schedule cada hora. Post-Azure: webhook + schedule diario como reconciliación. El contacto técnico backend de Pangi validó el diseño; hoy no se puede suscribir porque su `WebhookService` entrega a una sola URL de WordPress. |
| Widget | Standalone vía script tag. Tokens: `#1B1D4B`, `#8AC43F`, Open Sans. |
| Catálogos | Pangi es la fuente de verdad. Cero listas duplicadas. |
| WhatsApp | **No es prioridad.** Solo notificaciones salientes, sin agentes conversacionales, y después del widget. Evolution API queda descartada: se usará la Cloud API oficial de Meta. |
| n8n vs LangGraph | **Se queda n8n.** Migrar no genera valor para el CEO de Pangi hoy. La arquitectura híbrida (n8n en los bordes, LangGraph en el core) queda como discusión post-demo. |

---

## 3. Riesgos

| # | Riesgo | Estado | Mitigación |
|---|---|---|---|
| R1 | **PIN por SMS bloquea la reserva.** NOVA no puede completar una cita sola. | 🔴 Abierto — alto | Decisión conjunta el contacto técnico backend de Pangi + el CEO de Pangi. Recomendación: ruta de servicio que omita verificación, ya que el paciente está autenticado por JWT. |
| R2 | Semántica invertida de `booked` | ✅ **Cerrado 18 ago** | el contacto técnico backend de Pangi confirmó: `booked: true` = disponible. |
| R3 | Catálogo de cirugía plástica reconstructivo, no estético | ✅ **Cerrado 18 ago** | 10 procedimientos estéticos cargados en el Admin, en tres idiomas. |
| R4 | Solo 3 de 13 ciudades tienen médicos activos | 🟡 Aceptado | Nos acomodamos a las ciudades que existen. Se llenará cuando Pangi opere. |
| R5 | Sin estimates reales, ATLAS no es demostrable | 🔴 Abierto — medio | Crear estimates de prueba con un médico de confianza |
| R6 | Dependencia de disponibilidad del contacto técnico backend de Pangi | 🟢 Bajo | Todo lo público va primero. El encargado de infraestructura Azure del lado Pangi absorbió la infra, sacándola del camino del contacto técnico backend de Pangi. |
| R7 | Endpoint público exponía hashes, OTP y correos | ✅ **Cerrado 17 ago** | el contacto técnico backend de Pangi lo corrigió la misma noche. Era código heredado. |
| R8 | **Contexto clínico saliendo a Langfuse Cloud** (procedimiento, condiciones, medicamentos, edad, sexo) sin BAA | 🟡 Aceptado temporalmente | El PHI Strip remueve identificadores directos, así que no hay PHI bajo Safe Harbor. **Condición de salida: no se habilita a pacientes reales sin Langfuse autohospedado.** |
| R9 | ¿Cómo rutea Pangi una solicitud a los proveedores? | 🔴 Abierto — medio | Si es por el array `procedures`, los 4 dentales mapeados a la lista granular podrían no alcanzar a ningún médico. Pregunta B9. |

---

# PISTA A — Erick (independiente)

## F1 · Catálogos reales — ✅ CERRADA
**17–20 ago · Sin dependencias**

| # | Tarea | Estado |
|---|---|---|
| F1.1 | Workflow `06_pangi_catalog_sync` | ✅ Schedule horario · 21 especialidades / 163 procedimientos / 36 ciudades |
| F1.2 | Tabla de mapeo `procedure_key` ↔ string de Pangi | ✅ Migraciones 004 + 005 · 22/22 |
| F1.3 | Mapeo de ciudades | ✅ 36 sincronizadas con banderas `in_catalog` / `has_doctors` |
| F1.4 | Informe de brechas para el CEO de Pangi | ✅ Enviado 18 ago · aprobó cargar los estéticos |

**Entregable cumplido:** ambos agentes leen el catálogo real de Pangi.
Cero listas hardcodeadas.

**Alcance real vs. planificado:** el descubrimiento reveló **siete**
listas duplicadas que el roadmap no contemplaba — tres en NOVA
(`CITY_CANON`, `KNOWN`, `KNOWN_SCHED`), cuatro en SAGE (una de ellas en
el estado `summary`), más una quinta en el nodo de NLG que incluía
`Miami` y `San José, CR`, destinos que no existen en Pangi. Todas
unificadas.

**Nota:** los agentes leen el catálogo **desde PostgreSQL**, no llaman a
la API de Pangi en el camino crítico de la conversación. Si Pangi cae,
degradan con el último catálogo conocido.

## F2 · Schema v2 + operaciones de catálogo — ✅ CERRADA
**19–20 ago**

| # | Tarea | Estado |
|---|---|---|
| F2.1 | Migraciones de integración | ✅ 004 a 009 aplicadas |
| F2.2 | Estados de `medical_intake`: `submitted` vs `published` | ✅ Documentado en 004 · se cablea en F4.4 |
| F2.3 | Operaciones `getCities` / `getProcedures` + cableado de agentes | ✅ 22 operaciones en el router |
| F2.4 | Limpieza de `message_dedup` | ✅ Operación `cleanupMessageDedup` + `07_maintenance` |

**Hallazgo:** `cleanupExpiredSessions` existía desde el MVP pero **ningún
workflow la llamaba**. Como `idx_one_active_session_per_user` solo
permite una sesión no expirada por usuario, una sesión vencida sin
marcar seguía bloqueando la creación de una nueva. `07_maintenance` le
da un llamador.

## F3 · NOVA contra la API real — 🟡 EN PROGRESO
**F3-A, F3-B, F3-C cerrados · F3-D en diseño · F3-E bloqueada por el contacto técnico backend de Pangi**

| # | Tarea | Estado |
|---|---|---|
| F3-A | Sincronizar doctores/clínicas/procedimientos a `pangi_doctors`, `pangi_clinics`, `pangi_doctor_procedures` vía `06_pangi_catalog_sync` | ✅ `f3a-doctors-sync` |
| F3-B | NOVA lee doctores reales (nombres, títulos, clínicas, modalidad). Estrellas solo si `review_count > 0`; se muestra `years_experience` | ✅ `f3b-nova-doctors` |
| F3-C | NOVA lee horarios reales vía `date-slots-range` (endpoint que el contacto técnico backend de Pangi construyó a pedido, no estaba en el plan original) | ✅ `f3c-real-slots` |
| F3-D | Preguntar `visit_reason`, `payment_type`, `have_insurance` antes de reservar | 🟡 Diseño de capas listo, falta contrato del backend |
| F3-E | Reservar de verdad vía `POST /api/service/add-appointment` (no exige PIN, confirmado) | 🔴 Bloqueada — Swagger no documenta el cuerpo |

**Ya no hay dependencias del contacto técnico backend de Pangi para lo cerrado.** `/api/service/*` está en
producción (`health` → 200 con la service key), pero el body de
`add-appointment` no aparece en el Swagger (`OBLIGATORIOS: []`, sin
propiedades) — hay que pedírselo antes de F3-E.

### Aprendizajes de F3-C (importan para cualquier trabajo futuro con horarios)
- `date-slots-range?doctor_id=&date=&clinic_address=&limit=&days=` devuelve
  los N horarios más cercanos en una sola llamada, ya sin horas pasadas,
  en la zona del médico. Reemplazó el diseño original de 6 llamadas
  paralelas por día.
- `clinic_address` SIEMPRE explícito — sin él el servidor devuelve
  `time_zone: "-330"` (default de India).
- El margen de anticipación (12h presencial / 3h video) es política propia,
  no de Pangi. Se aplica eligiendo **desde cuándo se pide** la disponibilidad,
  no filtrando después: pedir desde hoy devolvía solo horarios que el
  filtro iba a descartar, y un médico con el día libre entero parecía sin
  disponibilidad — castigaba al que más agenda tenía.
- `limit=10`: el endpoint devuelve los N más cercanos, no N repartidos por día.
- Zona horaria mencionada UNA vez en el encabezado; horarios siempre en
  hora local del médico (así los guarda Pangi).
- `sched_slots` reconoce "otro especialista" y vuelve al picker mostrando
  las fichas — antes el paciente quedaba atrapado entre elegir horario o
  cancelar toda la conversación.

### Mejoras futuras (no bloqueantes)
- **C2**: si `date-slots-range` no encuentra nada en 7 días, ofrecer que
  el paciente proponga una fecha concreta. Poco frecuente en la práctica
  (verificado: Natalia mostró disponibilidad recién el día 4).
- **F3-D capa 3**: motivo de visita por texto libre con NLU, si el
  paciente rechaza los 7 procedimientos más comunes del médico.

### Diseño de F3-D — motivo de visita, en 3 capas
1. **Propuesta desde SAGE**: si el procedimiento que el paciente cotizó
   con SAGE está entre los que ofrece el médico elegido, se propone
   directamente ("Motivo: Ortodoncia — ¿correcto?").
2. **Los 7 más comunes del médico**: algunos dentistas tienen hasta 48
   procedimientos (códigos de facturación granulares). Verificado con
   datos reales: hay un salto natural de frecuencia entre médicos —
   Teeth Whitening (15), Orthodontics (14), Dental Implants (14), Veneers
   (13), Crowns and Bridges (13), Full Mouth Reconstruction (13), Root
   Canal Therapy (13), y luego cae a 9. Esos 7 coinciden con los
   comerciales del catálogo de Pangi. Es un `ORDER BY` sobre
   `pangi_doctor_procedures`, no una lista a mano.
3. **Abierta / "ninguno de estos"** — diferida como mejora futura.

### Pendiente de verificar antes de F3-D
- Si `GET /api/service/patient-summary` incluye el seguro del paciente
  (evitaría preguntarlo si ya está registrado). `have_insurance` se
  pregunta siempre si no.

## F6 · Widget
**31 ago – 11 sep · Sin dependencias técnicas · PRIORIDAD sobre WhatsApp**

| # | Tarea |
|---|---|
| F6.1 | Launcher, lista de mensajes, input — tokens de Pangi |
| F6.2 | Conexión al webhook de n8n |
| F6.3 | Adjuntos: selección, preview, validación (JPG/PNG/PDF) |
| F6.4 | Recepción del JWT desde Angular |
| F6.5 | Responsive + accesibilidad |

---

# PISTA B — el contacto técnico backend de Pangi y el encargado de infraestructura Azure del lado Pangi (infra)

| # | Tarea | Quién | Estado |
|---|---|---|---|
| **B1** | Corregir exposición de datos en `/api/common/doctors` | el contacto técnico backend de Pangi | ✅ **17 ago** |
| **B2** | Credencial de servicio (API key + Azure Key Vault) — 3–5 d | el contacto técnico backend de Pangi | 🔴 Bloquea F4, F5 |
| **B3** | `GET /api/assistant/patient-summary` — 1–2 d | el contacto técnico backend de Pangi | 🔴 Bloquea F4.1 |
| **B4** | Decisión + ruta de servicio para reservar (resuelve R1) — 2–3 d | el contacto técnico backend de Pangi + el CEO de Pangi | 🔴 Bloquea F3.6 |
| **B5** | 4 eventos webhook + teléfono plaintext + idioma — 2–3 d | el contacto técnico backend de Pangi | 🟡 Baja prioridad (F8) |
| **B6** | Provisionar VM + PostgreSQL | **El encargado de infraestructura Azure del lado Pangi** | 🟡 **19 ago** |
| **B7** | Confirmar semántica de `booked` | el contacto técnico backend de Pangi | ✅ **18 ago** |
| **B8** | Payload de `add-appointment` y forma de `post-treatment-with-estimate` | el contacto técnico backend de Pangi | 🔴 Bloquea F5.1 |
| **B9** | ¿Cómo se rutea un `post_treatment` a los proveedores? ¿Por `category`, `addresses`, `procedures`? | el contacto técnico backend de Pangi | 🔴 Resuelve R9 |

**Prioridad sugerida para el contacto técnico backend de Pangi:** B2 (desbloquea más) → B4 → B8 y B9 (responder) → B3 → B5

**Nota sobre B5:** los 4 eventos quedaron pendientes de definición. Principio acordado: *solo notificamos lo que el paciente no sabe todavía.* `estimate.accepted` se descarta —el paciente acaba de aceptarla— y se evalúa `appointment.booked` en su lugar según quién ejecuta el rechazo de un estimate.

---

# FASES DEPENDIENTES

## F4 · SAGE escribe en Pangi
**Depende de B2 + B3**

| # | Tarea | Detalle |
|---|---|---|
| F4.1 | `gathering_profile` condicional | Leer perfil de Pangi. Si ya existe, **no preguntar**. |
| F4.2 | Normalizar el Q&A con Claude | Hoy se guarda literal, con typos. Debe llegar limpio y legible para el médico. |
| F4.3 | Construir `medical_description` | Q&A estructurado en texto formateado, en el idioma del paciente |
| F4.4 | Operación `createPostTreatment` | Multipart. Guardar el `_id` devuelto como `pangi_post_treatment_id` y marcar `published`. |
| F4.5 | Manejo de archivos | Nueva rama en el motor para `messageType: 'file'`. Mapear a `xray_picture` / `labresult_picture` / `treatment_pictures`. Actualizar `completeness_score`. |
| F4.6 | Guías fotográficas de Pangi | Enlazar los PDFs `doc_es`/`doc_en`/`doc_pt` por especialidad que Pangi ya tiene |
| F4.7 | Respetar `allow_number_of_procedure` | Dental 3 · plástica 3. Leer del catálogo sincronizado, no hardcodear. |

## F3.6 · NOVA reserva de verdad
**Depende de B4**

Ejecutar la reserva según la decisión de R1, y persistir la cita — hoy la referencia `PA-XXXXXX` es aleatoria y se pierde al expirar la sesión.

## F5 · ATLAS con estimates reales
**Depende de B2 + B8 + que existan estimates**

| # | Tarea |
|---|---|
| F5.1 | Operación `getPangiEstimates` por `post_treatment_id` |
| F5.2 | Retirar `quotes_comparison` y `saveQuote` (huérfana, causa raíz del "Tienes 0") |
| F5.3 | Adaptar el comparador al shape real de `PreTreatmentEstimate` |
| F5.4 | Cruzar con `atlas_destinations` para costo total de viaje |

## F7 · Migración a Azure
**Depende de B6 · Estimado: desde el 19 ago**

n8n + LiteLLM en la VM, PostgreSQL gestionado aparte. **Reconstruir en paralelo, no migrar** — los workflows son JSON portable y el schema es SQL versionado.

Rehacer a mano: credenciales de n8n, URLs de webhook, config de LiteLLM.

**No migran:** Evolution API (descartada) ni la app del otro cliente que convive en el VPS. El VPS de Contabo se desmantela; el sandbox pasa al VPS propio con Docker.

**Pendiente de F7:** n8n hoy corre por npm + systemd. En Azure va en Docker, por reproducibilidad. La versión en Azure debe ser **igual o mayor** a 1.121.3 — los workflows no se importan hacia atrás.

## F8 · Notificaciones WhatsApp
**Depende de B5 + F7 · Baja prioridad**

Workflow `Pangi Webhook → validar HMAC → transformar → WhatsApp Cloud API`.

**Nota:** la Cloud API de Meta exige plantillas pre-aprobadas categoría Utility para mensajes fuera de la ventana de 24 h. La aprobación toma días — iniciar temprano, pero solo cuando el widget esté funcionando.

---

# CRONOGRAMA

| Semana | Erick | el contacto técnico backend de Pangi / el encargado de infraestructura Azure del lado Pangi |
|---|---|---|
| **17–21 ago** | ✅ F1.2 · F1.3 · F1.4 · F2.1 — F1.1 sync · F7 setup VM | ✅ B1 · B7 — B6 (el encargado de infraestructura Azure del lado Pangi 19 ago) · B2 |
| **24–28 ago** | F3 NOVA con API real · F7 migración | B2 · B4 decisión PIN |
| **31 ago–4 sep** | F6 widget · F4 si B2 llegó | B3 · B8 · B9 |
| **7–11 sep** | F4 SAGE escritura · F3.6 reserva | B5 webhooks |
| **14–18 sep** | F5 ATLAS · QA | soporte |
| **21–25 sep** | Widget en staging · QA integral | soporte |

**Demo integrado al CEO de Pangi: última semana de septiembre.**

Márgenes deliberadamente holgados: las estimaciones del contacto técnico backend de Pangi dependen de prioridad de sprint, y F4 no puede empezar sin B2.

---

# HITOS

| Hito | Criterio de aceptación | Fecha objetivo |
|---|---|---|
| **H1 — Catálogo vivo** | el CEO de Pangi agrega una ciudad en el Admin y SAGE la ofrece sin cambio de código | 22 ago |
| **H2 — NOVA con datos reales** | NOVA lista médicos y horarios reales de Pangi | 29 ago |
| **H3 — Primera escritura** | Una conversación con SAGE crea un `post_treatment` visible en Pangi | 5 sep |
| **H4 — Ciclo completo** | Solicitud → estimate del médico → ATLAS compara | 18 sep |
| **H5 — Widget en staging** | Chat embebido en pangi.com staging, extremo a extremo | 25 sep |
| **H6 — Listo para pacientes** | Langfuse autohospedado · VM en 16 GB · BAA confirmado | Antes de producción |

---

# ANEXO A — Contratos verificados

## Endpoints públicos

```
GET /api/common/speciality?lang=es|en|pt
GET /api/common/countries
GET /api/common/available-locations
GET /api/common/doctors?patient_id=&specialty=&insurance=&gender=
    &language=&country=&rate=&filter=&location=&sortBy=&limit=10&skip=
GET /api/common/date-slots?doctor_id=&date=MM/DD/YYYY
    &clinic_address=&patient_id=
GET /api/common/specilities?name=Dental%20Care     (sic, con typo)
```

## Autenticados (requieren credencial)

```
POST /api/patient/post-treatment-concern      (multipart)
GET  /api/patient/post-treatment-with-estimate?post_id=
GET  /api/patient/get-profile
GET  /api/patient/get-medical-information?patient_id=
GET  /api/common/get-medical-records?patient_id=
GET  /api/patient/family-members?status=verified
POST /api/patient/add-appointment              (bloqueado por PIN)
```

## `post-treatment-concern` — contrato real

| Campo | Tipo | Ejemplo |
|---|---|---|
| `patient_id` | string | `6a80d576c0b60daab6822cf3` |
| `category` | string (inglés) | `Dental Care` |
| `procedures` | array de strings | `["Dental Implants"]` |
| `addresses` | array de strings | `["Medellín","Bogota"]` |
| `description` | texto libre | breve |
| `medical_description` | **texto libre** | ← Q&A clínico de SAGE |
| `is_for_patient` | bool | `true` |
| `xray_picture` etc. | binario | multipart |

**Respuesta:** incluye `_id` y `pre_treatment_estimates: []`

## `date-slots` — contrato real

```json
{ "slotValues": [{ "slot": "15:00", "booked": true }],
  "time_zone": "America/Bogota" }
```

- `booked: true` = **disponible** · `booked: false` = no reservable *(confirmado por el contacto técnico backend de Pangi, 18 ago)*
- Las citas ya tomadas no aparecen en la respuesta
- `slotValues` varía por día: es la agenda configurada del médico

## Correcciones a lo que el contacto técnico backend de Pangi indicó

| El contacto técnico backend de Pangi dijo | Realidad |
|---|---|
| Tratamientos por `_id` de Mongo | Son **strings** dentro de `sub_speciality`. Sin `_id`. |
| `POST /api/patient/get-doctor-availability` | `GET /api/common/date-slots` |
| Sin webhooks de citas/estimates | Correcto, confirmado |

`sub_speciality` es un **string con JSON adentro** — requiere `JSON.parse()`. Igual `states` y `cities` en `countries`.

**Traducciones (actualizado 18 ago):** `sub_speciality_es` y `sub_speciality_pt` **sí funcionan** — estaban vacíos porque nadie los había cargado. Cirugía plástica ya tiene los 15 en tres idiomas. Dental sigue vacío: son 48 ítems, arreglos posicionales (todo o nada), con terminología de codificación odontológica que conviene validar con un dentista. No bloquea nada; la KB de Erick tiene los nombres en español.

---

# ANEXO B — Pendientes de decisión

| # | Tema | Decide | Estado |
|---|---|---|---|
| D1 | PIN por SMS en la reserva | el CEO de Pangi + el contacto técnico backend de Pangi | 🔴 Abierto |
| D2 | `completeness_score`: `* 85` vs `* 100` para el demo | Erick + el CEO de Pangi | 🔴 Abierto |
| D3 | Precedencia perfil Pangi vs. sesión | Erick + el contacto técnico backend de Pangi | 🔴 Abierto |
| D4 | Queries parametrizadas antes de producción/HIPAA | Erick | 🔴 Abierto |
| D5 | `clinical_intake` en fase 2 | el CEO de Pangi + el contacto técnico backend de Pangi | 🟡 Diferido |
| D6 | Cloud API de Meta — costo y número | el CEO de Pangi | 🟡 Diferido |
| D7 | BAA de Microsoft en la suscripción de Azure | el CEO de Pangi | 🔴 Preguntado al encargado de infraestructura Azure del lado Pangi |
| D8 | Arquitectura híbrida n8n + LangGraph | Erick | 🟡 Post-demo |

---

# ANEXO C — Pendientes menores registrados

- **Traducciones de dental** (48 procedimientos, ES/PT) — requiere criterio odontológico. La lista además tiene duplicación conceptual: `Veneers` / `Porcelain Veneers & Bonding` / `Porcelain veneer (per tooth)`, `Root Canal Therapy` / `Endodontics (Root Canal)`. Vale depurarla antes de traducir.
- **Los 5 procedimientos reconstructivos de Pangi** (reconstrucción mamaria, mano, quemaduras, labio leporino, microcirugía) no tienen preguntas clínicas ni exámenes en la KB. Si un paciente los pide, SAGE no puede guiarlo.
- **Especialidad `Cosmetic Surgery` duplicada** — apagada, sin médicos, con los mismos 5 procedimientos reconstructivos. Candidata a eliminar del Admin.
- **`Teeth Cleaning (Prophylaxis) `** tiene espacio final en Pangi. Los strings se copian literalmente, nunca se escriben a mano.
- **Puerto 5678 cerrado en el VPS** (18 ago) — n8n escuchaba en todas las interfaces con el firewall abierto. Nginx hace proxy por `localhost`, así que no se rompió nada.
- **Alias de LiteLLM** — verificar tras migrar a Azure. Un alias mal configurado ya causó fallos silenciosos de NLG.
- **`cleanup_expired_sessions()` es `RETURNS void`** — no informa cuántas
  sesiones marcó, así que `07_maintenance` no tiene visibilidad de eso.
  Mejorable cambiando la función en Postgres.
- **Estado `complete` no entiende "cotizar en otra ciudad"** — responde
  sobre ATLAS en bucle. Requiere decidir si agregar destinos a la
  solicitud publicada o crear una nueva; depende del contrato de F4.
- **SAGE no maneja archivos** — promete recibir fotos y exámenes pero no
  tiene rama para `messageType: 'file'`. Es F4.5.

---

*Documento vivo. Actualizar conforme lleguen respuestas del contacto técnico backend de Pangi y avance la ejecución.*