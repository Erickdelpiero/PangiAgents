# Roadmap de Integración — Agentes Pangi

**Proyecto:** NOVA · SAGE · ATLAS → plataforma Pangi
**Responsable IA:** Erick Del Piero Gonzales
**Contraparte técnica:** el contacto técnico backend de Pangi "el contacto técnico backend de Pangi" (Full Stack, Pangi)
**Decisor:** el CEO de Pangi (CEO)
**Inicio:** lunes 17 de agosto de 2026
**Punto de retorno:** tag `mvp-v2-pre-pangi` en `pangi-dev`

---

## 0. Estado de partida

**Lo que ya funciona:** sistema conversacional de tres agentes sobre n8n + Claude, multilenguaje (es/en/pt), handoffs sin pérdida de contexto, KB clínica de 22 procedimientos, PHI de-identificado antes de cada llamada al LLM, demostrado a el CEO de Pangi sin fallas.

**Lo que está simulado:** todo lo que toca a Pangi. SAGE "publica" cambiando un flag en su propio PostgreSQL. NOVA genera una referencia de cita aleatoria en memoria que no persiste en ningún lado. ATLAS lee una tabla que nadie llena.

**Lo que se descubrió (sesión DevTools, 15–16 ago):** contratos reales de la API de Pangi verificados contra producción. Ver Anexo A.

**Hallazgo estructural clave:** `05_db_manager` (workflow `ancJzcIbrd9T9QJB`) es un router con allowlist de 19 operaciones, y es la **única** superficie de datos del sistema. Ningún agente toca la base directamente. Integrar con Pangi significa cambiar el origen de datos de operaciones puntuales en ese workflow — **no reescribir SAGE, NOVA ni ATLAS.**

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
| Alcance de especialidades | Solo **dental** y **cirugía plástica**. Lo que falte de un lado se agrega del otro. |
| Persistencia | **Opción A**: PostgreSQL guarda el borrador; al confirmar, UNA llamada crea el `post_treatment` en Pangi y se guarda el `_id` de vuelta. |
| Campo clínico | `medical_description` (ya existe). **No se pide `clinical_intake`** — evita tocar el esquema core de Pangi. Se evalúa en fase 2. |
| Hosting | VM dedicada dentro del Azure de Pangi + Azure Database for PostgreSQL (gestionado). |
| Widget | Standalone vía script tag. Tokens: `#1B1D4B`, `#8AC43F`, Open Sans. |
| Catálogos | Pangi es la fuente de verdad. Cero listas duplicadas. |
| WhatsApp | Solo notificaciones salientes. Sin agentes conversacionales, por HIPAA. |

---

## 3. Riesgos abiertos

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | **PIN por SMS bloquea la reserva.** NOVA no puede completar una cita sola. | Alto — mata el flujo de NOVA | Decisión conjunta el contacto técnico backend de Pangi + el CEO de Pangi. Recomendación: ruta de servicio que omita verificación, ya que el paciente está autenticado por JWT. |
| R2 | Semántica invertida de `booked` | Medio — falla silenciosa | Confirmar con el contacto técnico backend de Pangi. Evidencia fuerte de que `true` = disponible. |
| R3 | Catálogo de cirugía plástica en Pangi es reconstructivo, no estético | Medio | Configuración en Admin con el CEO de Pangi (F1.4) |
| R4 | Solo 3 de 13 ciudades tienen médicos activos | Medio — ATLAS sin qué comparar | Ajustar expectativa del demo o poblar más médicos |
| R5 | Sin estimates reales, ATLAS no es demostrable | Medio | Crear estimates de prueba con un médico de confianza |
| R6 | Dependencia de disponibilidad de el contacto técnico backend de Pangi | Medio | Todo lo público va primero; lo autenticado después |
| R7 | **Endpoint público expone hashes de contraseña, OTP y correos de médicos** | Alto (seguridad) | Reportar a el contacto técnico backend de Pangi. Arreglo de una línea (`.select()`) |

---

# PISTA A — Erick (independiente)

## F1 · Catálogos reales
**17–21 ago · Sin dependencias**

| # | Tarea | Detalle |
|---|---|---|
| F1.1 | Cliente de catálogos | Consumir los 3 endpoints públicos de catálogo. Parsear `sub_speciality` (string con JSON adentro). Caché con TTL. |
| F1.2 | Tabla de mapeo | `procedure_key` ↔ string exacto de `sub_speciality`. La KB conserva las traducciones es/pt: Pangi solo tiene inglés. |
| F1.3 | Mapeo de ciudades | Alias es/en → nombre exacto de Pangi. Ojo: `Bogota` sin tilde, `Mexico City` no `Ciudad de México`. |
| F1.4 | **Informe de brechas para el CEO de Pangi** | Qué falta en el Admin de Pangi vs. qué falta en la KB. Cirugía plástica es el caso grande: catálogo reconstructivo vs. procedimientos estéticos. |

**Entregable:** ambos agentes leyendo catálogo real de Pangi. Fin de las listas hardcodeadas.

## F2 · Schema v2 + operaciones de catálogo
**19–22 ago · Depende de F1.2**

| # | Tarea | Detalle |
|---|---|---|
| F2.1 | Migración `004_pangi_integration.sql` | `users.pangi_user_id VARCHAR(24)`, `users.phone` → nullable, `medical_intake.pangi_post_treatment_id`, `knowledge_base.pangi_procedure_name`, `atlas_destinations.pangi_city_name` |
| F2.2 | Estados de `medical_intake` | Separar `submitted` (usuario confirmó) de `published` (creado en Pangi). Hoy son lo mismo; post-integración no lo serán. |
| F2.3 | Nuevas operaciones en `05_db_manager` | `getPangiCatalog`, `getPangiDoctors`, `getPangiSlots` — todas contra endpoints públicos |
| F2.4 | Limpieza de `message_dedup` | `DELETE` de registros > 1 hora. Hoy crece sin límite. |

## F3 · NOVA contra la API real
**24–29 ago · Depende de F2.3 · No depende de el contacto técnico backend de Pangi**

| # | Tarea | Detalle |
|---|---|---|
| F3.1 | Reemplazar `mockQueryDoctors` | Llamada real. Filtrar ciudad en memoria desde `all_clinic_address[].city` (la API filtra por país, no por ciudad). |
| F3.2 | Nuevo paso: selección de clínica | `date-slots` exige `clinic_address`. La cadena real es doctor → clínica → fecha → slots. |
| F3.3 | Reemplazar `mockGetSlots` | `booked === true` significa **disponible**. Una llamada por día. Fecha en `MM/DD/YYYY`. |
| F3.4 | Zonas horarias reales | Usar el `time_zone` que devuelve la API. Convertir a la zona del paciente. |
| F3.5 | Modalidad desde datos reales | `appointment[].code` → `in_person` / `online` |

**Nota:** F3.4 cumple, con datos reales y sin trabajo extra, la gestión de zonas horarias que la propuesta original vendió a el CEO de Pangi como diferenciador de NOVA.

## F6 · Widget
**31 ago – 11 sep · Sin dependencias técnicas**

| # | Tarea |
|---|---|
| F6.1 | Launcher, lista de mensajes, input — tokens de Pangi |
| F6.2 | Conexión al webhook de n8n |
| F6.3 | Adjuntos: selección, preview, validación (JPG/PNG/PDF) |
| F6.4 | Recepción del JWT desde Angular |
| F6.5 | Responsive + accesibilidad |

---

# PISTA B — el contacto técnico backend de Pangi (Pangi)

| # | Tarea | Estimación | Bloquea |
|---|---|---|---|
| **B1** | 🔴 **Corregir exposición de datos** en `/api/common/doctors`: quitar `password`, `OTP`, `email`, `stripe_id` del `.select()` | 1 h | Nada, pero es urgente |
| **B2** | Credencial de servicio (API key + Azure Key Vault) | 3–5 d | F4, F5, F7 |
| **B3** | `GET /api/assistant/patient-summary` — edad, sexo, condiciones, medicamentos, idioma, teléfono | 1–2 d | F4.1 |
| **B4** | Decisión + ruta de servicio para reservar (resuelve R1) | 2–3 d | F3.6 |
| **B5** | 4 eventos webhook + teléfono en plaintext + idioma | 2–3 d | F8 |
| **B6** | Provisionar VM Azure + PostgreSQL gestionado | 2–3 d | F7 |
| **B7** | Confirmar semántica de `booked` | 5 min | R2 |
| **B8** | Payload de `add-appointment` y forma de `post-treatment-with-estimate` | 15 min | F5.1 |

**Prioridad sugerida para el contacto técnico backend de Pangi:** B1 (seguridad) → B7 y B8 (responder, 20 min) → B2 (desbloquea más) → B4 → B3 → B5 → B6

---

# FASES DEPENDIENTES

## F4 · SAGE escribe en Pangi
**Depende de B2 + B3 · Estimado: 1–5 sep si B2 llega el 24 ago**

| # | Tarea | Detalle |
|---|---|---|
| F4.1 | `gathering_profile` condicional | Leer perfil de Pangi. Si ya existe, **no preguntar**. |
| F4.2 | Normalizar el Q&A con Claude | Hoy se guarda literal, con typos. Debe llegar limpio y legible para el médico. |
| F4.3 | Construir `medical_description` | Q&A estructurado en texto formateado, en el idioma del paciente |
| F4.4 | Operación `createPostTreatment` | Multipart. Guardar el `_id` devuelto como `pangi_post_treatment_id`. |
| F4.5 | Manejo de archivos | Nueva rama en el motor para `messageType: 'file'`. Mapear a `xray_picture` / `labresult_picture` / `treatment_pictures`. Actualizar `completeness_score`. |
| F4.6 | Guías fotográficas de Pangi | Enlazar los PDFs `doc_es`/`doc_en`/`doc_pt` por especialidad que Pangi ya tiene |
| F4.7 | Respetar `allow_number_of_procedure` | Dental permite 3; el resto, 1 |

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
**Depende de B2 + B6 · Estimado: 14–25 sep**

n8n, PostgreSQL gestionado y Langfuse en VM dedicada. **Reconstruir en paralelo, no migrar** — los workflows son JSON portable y el schema es SQL versionado. El VPS de Contabo queda como sandbox sin PHI.

Rehacer a mano: credenciales de n8n, URLs de webhook, config de LiteLLM.

## F8 · Notificaciones WhatsApp
**Depende de B5 + F7**

Workflow `Pangi Webhook → validar HMAC → transformar → WhatsApp`. Plantillas es/en/pt para los 4 eventos.

**Nota:** para producción, la Cloud API oficial de Meta exige plantillas pre-aprobadas categoría Utility. La aprobación toma días — iniciar temprano.

---

# CRONOGRAMA

| Semana | Erick | el contacto técnico backend de Pangi |
|---|---|---|
| **17–21 ago** | F1 catálogos · F2 schema | B1 seguridad · B7/B8 responder · B2 credencial |
| **24–28 ago** | F3 NOVA con API real | B2 · B4 decisión PIN |
| **31 ago–4 sep** | F6 widget · F4 si B2 llegó | B3 patient-summary · B5 webhooks |
| **7–11 sep** | F4 SAGE escritura · F3.6 reserva | B5 · B6 Azure |
| **14–18 sep** | F5 ATLAS · F7 Azure | soporte |
| **21–25 sep** | F7 · F8 notificaciones · QA | soporte |

**Demo integrado a el CEO de Pangi: última semana de septiembre.**

Márgenes deliberadamente holgados: las estimaciones de el contacto técnico backend de Pangi dependen de prioridad de sprint, y F4 no puede empezar sin B2.

---

# HITOS

| Hito | Criterio de aceptación | Fecha objetivo |
|---|---|---|
| **H1 — Catálogo vivo** | el CEO de Pangi agrega una ciudad en el Admin y SAGE la ofrece sin cambio de código | 22 ago |
| **H2 — NOVA con datos reales** | NOVA lista médicos y horarios reales de Pangi | 29 ago |
| **H3 — Primera escritura** | Una conversación con SAGE crea un `post_treatment` visible en Pangi | 5 sep |
| **H4 — Ciclo completo** | Solicitud → estimate del médico → ATLAS compara | 18 sep |
| **H5 — Widget en staging** | Chat embebido en pangi.com staging, extremo a extremo | 25 sep |

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
```

## Autenticados (requieren credencial)

```
POST /api/patient/post-treatment-concern      (multipart)
GET  /api/patient/post-treatment-with-estimate?post_id=
GET  /api/patient/get-profile
GET  /api/patient/get-medical-information?patient_id=
GET  /api/common/get-medical-records?patient_id=
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

- `booked: true` = **disponible** · `booked: false` = no reservable
- Las citas ya tomadas no aparecen en la respuesta
- `slotValues` varía por día: es la agenda configurada del médico

## Correcciones a lo que el contacto técnico backend de Pangi indicó

| el contacto técnico backend de Pangi dijo | Realidad |
|---|---|
| Tratamientos por `_id` de Mongo | Son **strings** dentro de `sub_speciality`. Sin `_id`. |
| `POST /api/patient/get-doctor-availability` | `GET /api/common/date-slots` |
| Sin webhooks de citas/estimates | Correcto, confirmado |

`sub_speciality` es un **string con JSON adentro** — requiere `JSON.parse()`. Igual `states` y `cities` en `countries`.
`sub_speciality_es` y `sub_speciality_pt` están **vacíos** en las 22 especialidades.

---

# ANEXO B — Pendientes de decisión

| # | Tema | Decide |
|---|---|---|
| D1 | PIN por SMS en la reserva | el CEO de Pangi + el contacto técnico backend de Pangi |
| D2 | `completeness_score`: `* 85` vs `* 100` para el demo | Erick + el CEO de Pangi |
| D3 | Precedencia perfil Pangi vs. sesión | Erick + el contacto técnico backend de Pangi |
| D4 | Queries parametrizadas antes de Azure/HIPAA | Erick |
| D5 | `clinical_intake` en fase 2 | el CEO de Pangi + el contacto técnico backend de Pangi |
| D6 | Cloud API de Meta vs. Evolution | el CEO de Pangi (costo) |

---

*Documento vivo. Actualizar conforme lleguen respuestas de el contacto técnico backend de Pangi y avance la ejecución.*
