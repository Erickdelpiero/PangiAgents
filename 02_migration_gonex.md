# Pangi — Sistema de Asistentes Inteligentes
## Documentación Técnica v1.0.0

**Proyecto:** NOVA · SAGE · ATLAS — Agentes de IA para Pangi  
**Autor:** Erick Del Piero Gonzales — Ing. Mecatrónico, Especialización en IA  
**Versión:** 1.0.0  
**Fecha:** 16 de Marzo del 2026  
**Estado:** Funcional en entorno de desarrollo (VPS Cooperativa El Milagro)  
**Pendiente:** Migración a VPS GONEX + integración con Pangi.com y WhatsApp oficial  

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Infraestructura — VPS Cooperativa El Milagro](#3-infraestructura--vps-cooperativa-el-milagro)
4. [Base de Datos PostgreSQL — pangi_dev](#4-base-de-datos-postgresql--pangi_dev)
5. [Workflows N8N](#5-workflows-n8n)
6. [Agentes — NOVA, SAGE y ATLAS](#6-agentes--nova-sage-y-atlas)
7. [Integración WhatsApp — Evolution API V2](#7-integración-whatsapp--evolution-api-v2)
8. [Bugs Conocidos y Pendientes v1.0](#8-bugs-conocidos-y-pendientes-v10)
9. [System Prompts — Upgrade a Claude API](#9-system-prompts--upgrade-a-claude-api)
10. [Guía de Migración a GONEX](#10-guía-de-migración-a-gonex)
11. [Hoja de Ruta v2.0](#11-hoja-de-ruta-v20)

---

## 1. Resumen Ejecutivo

### Qué es el sistema

Sistema de tres asistentes inteligentes integrados en WhatsApp para Pangi, plataforma de turismo médico. Los agentes atienden pacientes en español (con arquitectura lista para inglés y portugués), guiándolos desde la orientación inicial hasta la elección del destino médico óptimo.

| Agente | Rol | Estado v1.0 |
|--------|-----|-------------|
| **NOVA** | Orientadora y gestora de citas | ✅ Funcional |
| **SAGE** | Especialista en cotizaciones médicas | ✅ Funcional |
| **ATLAS** | Consejero de turismo médico | ✅ Funcional |

### Qué hace cada agente

**NOVA** es el punto de entrada. Recibe cada mensaje nuevo, detecta la intención del usuario mediante keywords y estado de sesión, y deriva a SAGE o ATLAS según corresponda. También gestiona agendamiento básico de citas.

**SAGE** acompaña al paciente durante el proceso de cotización. Conduce una conversación estructurada que recopila la información mínima necesaria para que los médicos coticen con precisión. Cubre 22 procedimientos (12 dentales, 10 de cirugía plástica) con preguntas y exámenes requeridos específicos por procedimiento. Calcula un score de completitud de 0-100% y guarda el expediente en PostgreSQL.

**ATLAS** ayuda al paciente a tomar la decisión de destino. Cuando el paciente tiene cotizaciones de múltiples países, ATLAS calcula el costo total real del viaje (procedimiento + vuelo estimado + hotel + días de recuperación) y genera una comparación ordenada de menor a mayor costo. También ofrece un checklist pre-viaje personalizado por especialidad y destino.

### Qué NO hace v1.0 (intencionalmente)

- No tiene NLU ni NLG real (sin Claude API en v1.0 — toda la lógica es por keywords y state machine)
- No lee la base de datos de Pangi (requiere coordinación con el full stack de Pangi)
- No está integrado en la web de Pangi.com (requiere el widget de chat)
- No tiene el número de WhatsApp oficial de Pangi (usa instancia de prueba Test1)
- No cubre especialidades distintas a dental y cirugía plástica

---

## 2. Arquitectura del Sistema

### Diagrama de flujo

```
Usuario (WhatsApp)
       │
       ▼
Evolution API V2 (Test1)
  • Recibe mensaje entrante
  • Dispara webhook POST a N8N
       │
       ▼
00_orchestrator (N8N)
  • Extrae y valida mensaje (filtra grupos, estados, mensajes propios)
  • Maneja formato @lid y @s.whatsapp.net de Evolution API V2
  • Crea o recupera usuario por teléfono (PostgreSQL)
  • Crea o recupera sesión activa (max 1 por usuario, 24h vigencia)
  • Guarda mensaje entrante en historial
  • Router de intención (keywords + respeta agente activo)
  • Switch → deriva a 01_nova / 02_sage / 03_atlas
  • Envía respuesta por WhatsApp vía Evolution API
  • Actualiza sesión (agente activo + contexto)
  • Guarda mensaje saliente en historial
       │
  ┌────┴────────────────┐
  ▼         ▼           ▼
01_nova   02_sage    03_atlas
  │           │           │
  └─────┬─────┘           │
        ▼                 ▼
   05_db_manager   05_db_manager
   (todas las      (todas las
   operaciones DB) operaciones DB)
        │
        ▼
   PostgreSQL 16.13
   pangi_dev
```

### Principio de diseño clave

Todos los accesos a base de datos pasan por `05_db_manager`. Ningún workflow de agente toca la DB directamente. Esto centraliza la validación, sanitización SQL y manejo de errores en un único punto, facilitando debugging y mantenimiento.

### Patrón de contexto de sesión

El contexto de sesión es un objeto JSON almacenado en `sessions.context`. Cada agente tiene su propio namespace dentro del contexto:

```json
{
  "nova": { "state": "handoff_complete" },
  "sage": {
    "state": "questioning",
    "specialty": "dental",
    "procedure_key": "implante_dental",
    "procedure_name": "Implante Dental",
    "critical_questions": [...],
    "required_info": [...],
    "collected_data": { "numero_implantes": "2" },
    "current_q_index": 2,
    "completeness_score": 43,
    "intake_id": 12
  },
  "atlas": {
    "state": "comparison_done",
    "quotes": [...],
    "best_destination": "Cancún"
  }
}
```

Esto permite que los tres agentes coexistan en la misma sesión sin sobreescribirse.

### Sistema de handoff (warm transfer)

Cuando NOVA detecta que el usuario quiere cotizar, ejecuta el handoff a SAGE. El proceso:

1. `04_handoff_manager` registra el handoff en `agent_handoffs` (auditoría)
2. Actualiza `sessions.active_agent` a `'SAGE'`
3. Genera un mensaje warm transfer personalizado (en el idioma del usuario)
4. El orchestrator envía ese mensaje al usuario
5. En el siguiente mensaje, el Router detecta `active_agent = 'SAGE'` y deriva directo, sin interrumpir

El mensaje de transición no es genérico — tiene variantes aleatorias por par de agentes (NOVA→SAGE, SAGE→ATLAS, etc.) para que no suene robótico.

---

## 3. Infraestructura — VPS Cooperativa El Milagro

### Especificaciones del servidor

```
Proveedor:  Contabo
OS:         Ubuntu 24.04.3 LTS
RAM:        8 GB
Disco:      72 GB SSD (16 GB usados, 56 GB disponibles)
CPU:        3 vCores
Hostname:   vmi2857037
```

### Acceso SSH

```bash
ssh VPS-Contabo
# o directamente:
ssh erick_user@[IP_VPS]
# Usuario: erick_user (sudo completo)
```

### Servicios en el VPS — mapa de coexistencia

```
/
├── COOPERATIVA EL MILAGRO (NO TOCAR)
│   ├── MySQL 8.0          → cooperativa_db  → puerto 3306 (localhost)
│   ├── Flask + Gunicorn   → /var/www/cooperativa/
│   └── Nginx              → coopelmilagro.com (SSL Let's Encrypt)
│
├── PANGI (proyecto activo)
│   ├── PostgreSQL 16.13   → pangi_dev       → puerto 5432 (localhost)
│   ├── N8N v1.116.2       → /var/www/n8n/   → puerto 5678
│   └── Evolution API V2   → /var/www/evolution-api/ → puerto 8080
│
└── NGINX (reverse proxy compartido)
    ├── coopelmilagro.com      → Gunicorn (cooperativa)
    ├── n8n.coopelmilagro.com  → localhost:5678 (N8N)
    └── evolution.coopelmilagro.com → localhost:8080 (Evolution API)
```

### N8N — configuración relevante

```
Versión:    1.116.2 (npm, no Docker)
Instalación: /var/www/n8n/
Servicio:   systemd (n8n.service)
Usuario:    n8n_user
DB propia:  n8n_db (PostgreSQL, usuario n8n_db_user)
Puerto:     5678
URL pública: https://n8n.coopelmilagro.com
Env file:   /var/www/n8n/.env
```

Variables clave del `.env` de N8N:
```
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_HOST=n8n.coopelmilagro.com
WEBHOOK_URL=https://n8n.coopelmilagro.com/
DB_TYPE=postgresdb
DB_POSTGRESDB_DATABASE=n8n_db
NODE_FUNCTION_ALLOW_BUILTIN=*
NODE_FUNCTION_ALLOW_EXTERNAL=googleapis,fs,path
```

> **Nota importante:** N8N usa `DB_TYPE=postgresdb`, lo que significa que los workflows se guardan en PostgreSQL (`n8n_db`). Al migrar a GONEX, los workflows deben exportarse como JSON desde la interfaz de N8N y reimportarse — no se puede copiar la DB directamente porque los IDs de credenciales cambiarán.

### Evolution API V2 — configuración relevante

```
Versión:    V2
Instalación: /var/www/evolution-api/
Servicio:   systemd (evolution-api.service)
Puerto:     8080
URL pública: https://evolution.coopelmilagro.com
Manager UI:  https://evolution.coopelmilagro.com/manager
```

**Instancia activa para Pangi:** `Test1` (número de prueba conectado)

**Webhook configurado en Test1:**
```
URL: https://n8n.coopelmilagro.com/webhook/pangi-whatsapp-dev
Eventos: MESSAGES_UPSERT
```

> **CRÍTICO:** Usar siempre la URL de producción `/webhook/` (no `/webhook-test/`). La URL de test solo funciona cuando N8N está en modo "Listen for test event" manualmente.

### Firewall (UFW)

```
Puertos abiertos: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5678 (N8N directo)
```

> Puerto 5678 está abierto directamente. En producción (GONEX) considerar cerrarlo y forzar acceso solo vía Nginx con autenticación.

---

## 4. Base de Datos PostgreSQL — pangi_dev

### Conexión

```bash
psql -U pangi_user -h localhost -d pangi_dev
# Password: definido durante instalación (ver credenciales seguras)
```

### Usuario y permisos

```sql
-- Usuario creado con GRANT ALL en pangi_dev únicamente
-- No tiene acceso a n8n_db, evolution_db, chatbot_saas ni postgres
CREATE USER pangi_user WITH PASSWORD '...';
GRANT ALL PRIVILEGES ON DATABASE pangi_dev TO pangi_user;
```

### Esquema completo — 8 tablas

#### `users` — Usuarios del sistema

```sql
CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    phone         VARCHAR(30) UNIQUE NOT NULL,  -- formato: +51941915097
    name          VARCHAR(100),
    language      VARCHAR(5) DEFAULT 'es',       -- es | en | pt
    first_contact TIMESTAMPTZ DEFAULT NOW(),
    last_activity TIMESTAMPTZ DEFAULT NOW(),
    is_active     BOOLEAN DEFAULT TRUE,
    metadata      JSONB DEFAULT '{}'
);
```

Los usuarios se identifican por número de teléfono. Se crean automáticamente al primer contacto vía `getOrCreateUser` (upsert). El campo `language` permite futuro soporte multilingüe sin cambios de schema.

#### `sessions` — Sesiones de conversación

```sql
CREATE TABLE sessions (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER REFERENCES users(id),
    active_agent VARCHAR(10) DEFAULT 'NOVA',  -- NOVA | SAGE | ATLAS
    state        VARCHAR(50) DEFAULT 'initial',
    context      JSONB DEFAULT '{}',           -- estado interno de cada agente
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW(),
    expires_at   TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours'
);

-- Constraint crítico: máximo 1 sesión activa por usuario
-- Previene sesiones zombie que causaban el bug de routing principal en v1.0
CREATE UNIQUE INDEX idx_one_active_session_per_user
ON sessions (user_id)
WHERE state != 'expired';
```

**Diseño de sesión:** Se expiran sesiones anteriores al crear una nueva (CTE en `createSession`). La query `getActiveSession` prioriza sesiones de SAGE/ATLAS sobre NOVA para evitar que una sesión NOVA nueva tape una sesión de agente especialista.

#### `conversation_history` — Historial de mensajes

```sql
CREATE TABLE conversation_history (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER REFERENCES users(id),
    session_id   INTEGER REFERENCES sessions(id),
    agent        VARCHAR(10) NOT NULL,   -- NOVA | SAGE | ATLAS | ROUTER
    role         VARCHAR(10) NOT NULL,   -- user | assistant | system
    message      TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',  -- text | button_reply | image | audio
    created_at   TIMESTAMPTZ DEFAULT NOW()
);
```

Se guarda cada mensaje entrante y saliente. Cuando se integre Claude API, este historial se enviará como contexto de conversación para que Claude mantenga coherencia.

#### `medical_intake` — Expedientes de SAGE

```sql
CREATE TABLE medical_intake (
    id                 SERIAL PRIMARY KEY,
    user_id            INTEGER REFERENCES users(id),
    session_id         INTEGER REFERENCES sessions(id),
    specialty          VARCHAR(50) NOT NULL,    -- dental | plastic_surgery
    procedure_name     VARCHAR(100),
    collected_data     JSONB DEFAULT '{}',      -- respuestas del paciente
    missing_items      JSONB DEFAULT '[]',      -- exámenes faltantes
    completeness_score INTEGER DEFAULT 0,       -- 0-100%
    status             VARCHAR(20) DEFAULT 'in_progress',  -- in_progress | complete | submitted | cancelled
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    updated_at         TIMESTAMPTZ DEFAULT NOW()
);
```

**HIPAA:** Este tabla solo almacena datos que el usuario comparte voluntariamente en el chat. Los datos clínicos de la DB de Pangi se leerán en producción pero NUNCA se escribirán aquí.

#### `quotes_comparison` — Cotizaciones para ATLAS

```sql
CREATE TABLE quotes_comparison (
    id                      SERIAL PRIMARY KEY,
    user_id                 INTEGER REFERENCES users(id),
    intake_id               INTEGER REFERENCES medical_intake(id),
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
```

#### `atlas_destinations` — Destinos de turismo médico (datos estáticos)

```sql
CREATE TABLE atlas_destinations (
    id                           SERIAL PRIMARY KEY,
    country                      VARCHAR(100) NOT NULL,
    city                         VARCHAR(100) NOT NULL,
    avg_flight_cost_usd          NUMERIC(8,2),
    avg_hotel_cost_per_night_usd NUMERIC(8,2),
    avg_recovery_days_dental     INTEGER DEFAULT 3,
    avg_recovery_days_plastic    INTEGER DEFAULT 7,
    climate_type                 VARCHAR(50),
    languages                    VARCHAR(100) DEFAULT 'español',
    visa_required_us             BOOLEAN DEFAULT FALSE,
    notes                        TEXT,
    is_active                    BOOLEAN DEFAULT TRUE
);
```

**10 destinos cargados:** México (CDMX, Cancún), Colombia (Bogotá, Medellín, Cartagena), Perú (Lima), Costa Rica (San José), Argentina (Buenos Aires), República Dominicana (Santo Domingo), USA (Miami — referencia). Los costos son estimados estáticos para el MVP, pendientes de actualización con datos reales.

#### `knowledge_base` — Procedimientos y requisitos (SAGE)

```sql
CREATE TABLE knowledge_base (
    id                    SERIAL PRIMARY KEY,
    specialty             VARCHAR(50) NOT NULL,
    procedure_name        VARCHAR(100) NOT NULL,
    procedure_key         VARCHAR(100) UNIQUE NOT NULL,
    required_info         JSONB NOT NULL,      -- campos a recopilar
    critical_questions    JSONB NOT NULL,      -- preguntas para el paciente
    required_exams        JSONB DEFAULT '[]',  -- exámenes recomendados
    typical_recovery_days INTEGER,
    sage_intro_message    TEXT,
    is_active             BOOLEAN DEFAULT TRUE,
    created_at            TIMESTAMPTZ DEFAULT NOW()
);
```

**22 procedimientos cargados:**

*Dental (12):* extraccion_simple, extraccion_muela_juicio, implante_dental, protesis_completa, carillas_veneers, ortodoncia_brackets, ortodoncia_invisible, endodoncia, corona_dental, limpieza_profunda, blanqueamiento, puente_dental

*Cirugía Plástica (10):* rinoplastia, abdominoplastia, liposuccion, aumento_mamario, reduccion_mamaria, bichectomia, blefaroplastia, otoplastia, lifting_facial, bbl

> **⚠️ Importante:** Esta base de conocimiento fue construida con estándares clínicos generales. Debe ser revisada, validada y aprobada por los médicos de Pangi antes de salir a producción.

#### `agent_handoffs` — Log de transferencias

```sql
CREATE TABLE agent_handoffs (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER REFERENCES users(id),
    session_id       INTEGER REFERENCES sessions(id),
    from_agent       VARCHAR(10) NOT NULL,
    to_agent         VARCHAR(10) NOT NULL,
    reason           VARCHAR(200),
    context_snapshot JSONB DEFAULT '{}',
    created_at       TIMESTAMPTZ DEFAULT NOW()
);
```

Registro de auditoría de todos los handoffs. Útil para analizar patrones de uso y optimizar el routing.

### Índices de performance

```sql
CREATE INDEX idx_users_phone          ON users(phone);
CREATE INDEX idx_users_last_activity  ON users(last_activity);
CREATE INDEX idx_sessions_user_id     ON sessions(user_id);
CREATE INDEX idx_sessions_expires     ON sessions(expires_at);
CREATE INDEX idx_sessions_agent       ON sessions(active_agent);
CREATE INDEX idx_conv_user_id         ON conversation_history(user_id);
CREATE INDEX idx_conv_session_id      ON conversation_history(session_id);
CREATE INDEX idx_conv_created         ON conversation_history(created_at);
CREATE INDEX idx_intake_user          ON medical_intake(user_id);
CREATE INDEX idx_intake_specialty     ON medical_intake(specialty);
CREATE INDEX idx_kb_key               ON knowledge_base(procedure_key);
CREATE INDEX idx_kb_specialty         ON knowledge_base(specialty);
```

### Consultas de monitoreo útiles

```sql
-- Estado general de sesiones activas
SELECT u.name, u.phone, s.active_agent, s.state, s.updated_at
FROM sessions s JOIN users u ON u.id = s.user_id
WHERE s.state != 'expired'
ORDER BY s.updated_at DESC;

-- Historial de un usuario específico
SELECT agent, role, LEFT(message, 80) AS msg, created_at
FROM conversation_history
WHERE user_id = [ID]
ORDER BY created_at ASC;

-- Intakes en progreso
SELECT u.name, mi.specialty, mi.procedure_name,
       mi.completeness_score, mi.status
FROM medical_intake mi JOIN users u ON u.id = mi.user_id
WHERE mi.status != 'cancelled'
ORDER BY mi.updated_at DESC;

-- Expirar sesión manualmente (para pruebas)
UPDATE sessions SET state = 'expired'
WHERE user_id = [ID];

-- Verificar índice de sesión única
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'sessions';
```

---

## 5. Workflows N8N

### Estructura de archivos

```
~/Documents/Projects/pangi-dev/workflows/
├── 05_db_manager.json      Sub-workflow — acceso a DB
├── 04_handoff_manager.json Sub-workflow — transferencia entre agentes
├── 00_orchestrator.json    Workflow principal — entry point webhook
├── 01_nova.json            Agente NOVA
├── 02_sage.json            Agente SAGE
└── 03_atlas.json           Agente ATLAS
```

### `05_db_manager` — Base de Datos

**Tipo:** Sub-workflow (executeWorkflowTrigger)
**Estado:** Inactivo (llamado por otros workflows)
**Nodos:** 6

Motor único de acceso a PostgreSQL. Todos los demás workflows llaman a este sub-workflow en lugar de conectarse directamente a la DB.

**Contrato de entrada:**
```json
{
  "operation": "getOrCreateUser",
  "params": { "phone": "+51941915097", "name": "Erick", "language": "es" }
}
```

**18 operaciones disponibles:**

| Operación | Descripción |
|-----------|-------------|
| `getOrCreateUser` | Upsert de usuario por teléfono |
| `updateUserActivity` | Actualiza last_activity |
| `getActiveSession` | Sesión activa con prioridad SAGE/ATLAS |
| `createSession` | Crea sesión (expira anteriores via CTE) |
| `updateSession` | Actualiza agente, estado y contexto |
| `expireSession` | Expira una sesión |
| `saveMessage` | Guarda mensaje en historial |
| `getConversationHistory` | Historial paginado |
| `saveMedicalIntake` | Crea expediente de SAGE |
| `updateMedicalIntake` | Actualiza expediente |
| `getMedicalIntake` | Lee expediente activo |
| `getProcedure` | Lee procedimiento del KB por key |
| `getProceduresBySpecialty` | Lista procedimientos por especialidad |
| `saveQuote` | Guarda cotización para ATLAS |
| `getQuotes` | Lee cotizaciones del usuario |
| `getDestinations` | Lee destinos de ATLAS |
| `logHandoff` | Registra transferencia en auditoría |
| `cleanupExpiredSessions` | Limpieza de sesiones vencidas |

**Bug crítico resuelto en v1.0:** `alwaysOutputData: true` en el nodo PostgreSQL causaba que consultas con 0 resultados devolvieran `count: 1` con datos basura. Resuelto con filtro positivo en `📤 Formatear Respuesta Final` que detecta filas reales por presencia de campos propios de la DB (`id`, `created_at`, `procedure_key`, etc.).

### `04_handoff_manager` — Transferencias

**Tipo:** Sub-workflow
**Estado:** Inactivo
**Nodos:** 11

Gestiona las transferencias entre agentes. Arquitectura de errores diferenciada:
- Fallo en log de auditoría → **warning no bloqueante** (el handoff continúa)
- Fallo en actualización de sesión → **error bloqueante** (handoff cancelado para preservar consistencia)

Genera mensajes warm transfer en español, inglés y portugués con variantes aleatorias por par de agentes.

**Fix v1.0.1:** El patrón `inputData: JSON.stringify()` en nodos `executeWorkflow` no funciona en N8N v1. Se resolvió usando nodos `📦 Preparar Payload` (Code nodes) antes de cada `executeWorkflow`, que forman el objeto JSON correcto como item de salida.

### `00_orchestrator` — Orquestador Principal

**Tipo:** Webhook (entry point)
**Estado:** ACTIVO
**Nodos:** 26
**Webhook URL (producción):** `https://n8n.coopelmilagro.com/webhook/pangi-whatsapp-dev`

Flujo completo:

```
1. Webhook recibe POST de Evolution API
2. Extrae mensaje — soporta @lid y @s.whatsapp.net (fix remoteJidAlt)
3. Filtra: grupos, estados, mensajes propios
4. getOrCreateUser por phone
5. getActiveSession (prioridad SAGE/ATLAS sobre NOVA)
6. ¿Sesión existe? → normalizar existente / crear nueva
7. saveMessage (entrante)
8. Router de intención:
   - REGLA 1: Si active_agent = SAGE/ATLAS → mantener (no interrumpir)
   - REGLA 2: Botones interactivos → detectar por ID
   - REGLA 3: Keywords de texto (listas por intención)
9. Switch → NOVA / SAGE / ATLAS
10. Agente genera respuesta
11. Evolution API envía mensaje al usuario
12. updateSession (nuevo agente + contexto)
13. saveMessage (saliente)
```

**Bug crítico resuelto:** IF `✅ ¿Sesión Existe?` tenía el campo Right value vacío en vez de `0`. N8N con `typeValidation: strict` comparaba `1 > ""` = false, enviando siempre al branch de createSession aunque existiera sesión activa.

**Fix @lid:** Evolution API V2 envía `remoteJid` en formato `274942432129274@lid` (nuevo formato WhatsApp). El extractor ahora prioriza `key.remoteJidAlt` que siempre contiene el formato `@s.whatsapp.net` compatible con sendText.

### `01_nova`, `02_sage`, `03_atlas` — Agentes

**Tipo:** Sub-workflows
**Estado:** Inactivos (llamados por orchestrator)

Ver sección 6 para detalle de cada agente.

### Credenciales en N8N

| Nombre | Tipo | Uso |
|--------|------|-----|
| `Pangi DB (pangi_dev)` | Postgres | `05_db_manager` |
| `Evolution API - Pangi` | Header Auth (`apikey`) | `00_orchestrator` |
| `Claude API - Pangi` | Header Auth (`x-api-key`) | Listo para v2.0 |

> **Al migrar a GONEX:** Las credenciales no se exportan en los JSONs de N8N por seguridad. Deben recrearse manualmente en la nueva instancia y re-vincularse a los workflows correspondientes.

---

## 6. Agentes — NOVA, SAGE y ATLAS

### NOVA — Orientadora

**Archivo:** `01_nova.json`
**Nodos:** 5

NOVA opera como máquina de estados simple. Sus estados:

| Estado | Descripción |
|--------|-------------|
| `welcome` | Primer contacto — muestra menú |
| `initial_presented` | Menú mostrado, esperando elección |
| `gathering_appointment_city` | Recopilando ciudad para cita |
| `gathering_appointment_specialty` | Recopilando especialidad |
| `handoff_complete` | Derivó a SAGE o ATLAS |
| `active` | Conversación activa sin estado especial |
| `clarification_needed` | Intención no reconocida |

**Prioridad de respuesta:**
1. pendingHandoff = SAGE → warm transfer a SAGE
2. pendingHandoff = ATLAS → warm transfer a ATLAS
3. Estado de recopilación activo → continuar recopilación
4. intent = agendar → iniciar recopilación de cita
5. isNewSession → bienvenida con menú
6. intent = saludo → menú abreviado
7. fallback → menú de opciones

**Para v2.0:** El body de respuesta de NOVA será generado por Claude API con el system prompt de NOVA. La lógica de estados y handoffs permanece igual.

### SAGE — Especialista en Cotizaciones

**Archivo:** `02_sage.json`
**Nodos:** 10

SAGE es el agente más complejo. Opera como una máquina de estados que guía al paciente paso a paso:

| Estado | Descripción |
|--------|-------------|
| `welcome` / `handoff_received` | Bienvenida + selección especialidad |
| `selecting_specialty` | Detecta dental/cirugía plástica |
| `selecting_procedure` | Usuario elige de lista de 22 procedimientos |
| `procedure_confirmed` | KB cargado, inicia Q&A |
| `questioning` | Pregunta y guarda respuestas secuencialmente |
| `summary` | Resumen + score + espera confirmación |
| `complete` | Publicado, ofrece ATLAS |
| `handoff_to_atlas` | Transferencia a ATLAS |

**Score de completitud:**
- Base: (respuestas dadas / total preguntas) × 85%
- Bonus: +15% si se mencionan los exámenes requeridos
- Máximo: 100%

**Labels de score:**
- 80-100%: 🟢 Excelente
- 60-79%: 🟡 Buena
- 0-59%: 🔴 Básica

**Integración con KB:** SAGE carga el procedimiento del KB solo cuando `procedure_key` ya existe en el contexto (fue elegido en el mensaje anterior). Esto evita un round-trip innecesario al DB en el primer mensaje de cada estado.

**Bug cosmético pendiente v1.0:** Los labels del resumen final muestran las respuestas en el orden inverso al que fueron respondidas (efecto de cómo se mapean `required_info` keys vs `critical_questions`). Las respuestas se guardan correctamente en DB — solo la presentación está desfasada. Fix programado para v2.0.

**Para v2.0:** El Q&A conversacional será reemplazado por Claude API. Claude leerá el mensaje del paciente y extraerá los datos relevantes usando NLP, en vez de preguntar secuencialmente. El score y el resumen también serán generados por Claude para mayor naturalidad.

### ATLAS — Consejero de Turismo Médico

**Archivo:** `03_atlas.json`
**Nodos:** 10

| Estado | Descripción |
|--------|-------------|
| `welcome` / `handoff_received` | Bienvenida + ¿tiene cotizaciones? |
| `has_quotes_check` | Routing: sí/no tiene cotizaciones |
| `exploring` | Panorama de destinos con costos estimados |
| `entering_quotes` | Usuario ingresa cotizaciones manualmente |
| `analyzing` | Cálculo de costo total por destino |
| `comparison_done` | Análisis mostrado, ofrece checklist |
| `checklist_shown` | Checklist entregado |
| `handoff_to_sage` | Transferencia a SAGE |

**Fórmula de costo total:**
```
Total = procedimiento + vuelo_estimado + (hotel_por_noche × días_recuperación)
```

Los días de recuperación varían por tipo de procedimiento:
- Dental: `avg_recovery_days_dental` (generalmente 2-3 días)
- Cirugía plástica: `avg_recovery_days_plastic` (generalmente 7-21 días)

**Parser de cotizaciones:** Detecta precio con regex (`$XXX`, `XXX USD`, `XXX dólares`) y destino comparando texto contra nombres de ciudades y países en `atlas_destinations`. Funciona con formato libre: `Colombia - Medellín - $800` o `800 dólares en Medellín`.

**Fix v1.0.1:** El ingreso de cotizaciones ahora funciona desde el estado `exploring` (sin necesidad de transitar a `entering_quotes` primero). Se detecta el formato de cotización directamente en el estado exploring con el mismo parser.

**Para v2.0:** El parsing de cotizaciones del texto natural y la narrativa del análisis comparativo serán generados por Claude API para mayor precisión y personalización.

---

## 7. Integración WhatsApp — Evolution API V2

### Configuración actual (desarrollo)

```
Manager: https://evolution.coopelmilagro.com/manager
Instancia: Test1
Webhook: https://n8n.coopelmilagro.com/webhook/pangi-whatsapp-dev
Eventos: MESSAGES_UPSERT
```

### Formatos de mensaje soportados

| Tipo | Campo en payload | Descripción |
|------|-----------------|-------------|
| Texto | `message.conversation` | Mensaje de texto normal |
| Texto largo | `message.extendedTextMessage.text` | Texto con formato |
| Botón clásico | `message.buttonsResponseMessage.selectedButtonId` | Respuesta a botón |
| Lista | `message.listResponseMessage.singleSelectReply.selectedRowId` | Selección de lista |
| Botón nativo | `message.interactiveResponseMessage.nativeFlowResponseMessage` | Botones nativos WhatsApp |
| Imagen | `message.imageMessage.caption` | Imagen con caption |
| Audio | `message.audioMessage` | Audio/nota de voz |
| Documento | `message.documentMessage` | Archivos |

### Manejo del formato @lid

Evolution API V2 envía el `remoteJid` en dos formatos posibles:
- `274942432129274@lid` — formato nuevo de WhatsApp para cuentas vinculadas
- `51941915097@s.whatsapp.net` — formato tradicional

El orchestrator prioriza `key.remoteJidAlt` (siempre en formato @s.whatsapp.net) sobre `key.remoteJid` para compatibilidad con el endpoint `sendText` de Evolution API.

### Endpoint para envío de mensajes

```
POST https://evolution.coopelmilagro.com/message/sendText/Test1
Headers: apikey: [API_KEY]
Body: {
  "number": "51941915097@s.whatsapp.net",
  "text": "Mensaje aquí",
  "delay": 1000
}
```

> El campo `delay: 1000` simula tiempo de escritura para experiencia más natural.

### Al migrar a número oficial de Pangi

En Evolution API Manager, crear nueva instancia → conectar número oficial de Pangi → actualizar webhook a la URL del VPS GONEX → actualizar el campo `instance` en el orchestrator.

---

## 8. Bugs Conocidos y Pendientes v1.0

### Resueltos durante desarrollo

| Bug | Causa | Fix aplicado |
|-----|-------|-------------|
| Sesiones múltiples por usuario | Sin constraint DB | `UNIQUE INDEX` parcial + CTE en createSession |
| IF siempre va al FALSE path | Right value vacío en N8N | Configurado con valor `0` explícito |
| sessionId NaN en agentes | executeWorkflow con inputData como string | Code nodes preparadores antes de executeWorkflow |
| remoteJid null en Evolution API | Formato @lid no manejado | Prioridad a `remoteJidAlt` en extractor |
| ATLAS no acepta cotizaciones desde `exploring` | Estado machine incompleto | Añadido parser en estado `exploring` |
| `alwaysOutputData` causa count:1 con 0 filas | Comportamiento N8N v1.116 | Filtro positivo por campos de filas reales |

### Pendientes para v2.0

| Pendiente | Descripción | Prioridad |
|-----------|-------------|-----------|
| Labels resumen SAGE | Respuestas desfasadas en presentación final | Baja |
| NLU real | Reemplazar keywords por Claude API | Alta |
| NLG real | Reemplazar respuestas hardcoded por Claude API | Alta |
| Multilingüe | Activar inglés y portugués | Media |
| Integración DB Pangi | Leer historial médico del paciente en Pangi | Alta |
| Agendamiento real | NOVA conectada al sistema de citas de Pangi | Alta |
| Cotizaciones reales | ATLAS lee cotizaciones desde DB de Pangi | Alta |

---

## 9. System Prompts — Upgrade a Claude API

Los workflows están preparados para integrar Claude API. Cada mock handler en los agentes tiene un comentario `// Para v2.0: reemplazar por llamada a Claude API`. La integración requiere:

### Para cada agente — reemplazar el nodo motor por HTTP Request a Claude

```javascript
// Endpoint
POST https://api.anthropic.com/v1/messages

// Headers
x-api-key: [CLAUDE_API_KEY]
anthropic-version: 2023-06-01
content-type: application/json

// Body base
{
  "model": "claude-haiku-4-5-20251001",  // NOVA (velocidad)
  // "model": "claude-sonnet-4-6",       // SAGE y ATLAS (capacidad)
  "max_tokens": 1000,
  "system": "[SYSTEM_PROMPT del agente]",
  "messages": [
    // Historial de conversación desde conversation_history
    { "role": "user", "content": "mensaje del paciente" },
    { "role": "assistant", "content": "respuesta anterior del agente" }
    // ... últimos N mensajes
  ]
}
```

### System prompts — estructura recomendada

Los system prompts deben ir en `/prompts/` del proyecto. Cada uno define:
- Identidad y personalidad del agente
- Contexto del sistema Pangi
- Instrucciones específicas del agente (qué preguntar, cómo responder)
- Formato de respuesta esperado
- Lo que el agente NO debe hacer
- Idioma de respuesta

**Instrucción clave para todos los prompts:** El agente debe responder siempre en el idioma que el usuario está usando, detectándolo automáticamente del mensaje entrante.

### Costo operativo estimado con Claude API

| Componente | Costo estimado/mes |
|------------|-------------------|
| Claude Haiku (NOVA) | ~$5-10 USD |
| Claude Sonnet (SAGE + ATLAS) | ~$15-30 USD |
| PostgreSQL hosting | ~$0 (incluido en VPS) |
| N8N | ~$0 (self-hosted) |
| Evolution API | ~$0 (self-hosted) |
| **Total estimado** | **~$20-40 USD/mes** |

---

## 10. Guía de Migración a GONEX

### Pre-requisitos en VPS GONEX

Antes de iniciar la migración, el VPS GONEX debe tener:

- [ ] Ubuntu 24.04 LTS
- [ ] PostgreSQL 16+ instalado y corriendo
- [ ] N8N v1.116+ instalado (mismo método que VPS cooperativa, no Docker)
- [ ] Evolution API V2 instalado
- [ ] Nginx configurado como reverse proxy con SSL (Let's Encrypt)
- [ ] Dominio de Pangi apuntando al VPS GONEX

### Paso 1 — PostgreSQL: Crear base de datos

```bash
# En VPS GONEX
sudo -u postgres psql

# Crear usuario y base de datos
CREATE USER pangi_user WITH PASSWORD 'NUEVA_PASSWORD_SEGURA';
CREATE DATABASE pangi_dev
    WITH OWNER pangi_user
    ENCODING 'UTF8'
    LC_COLLATE 'C.UTF-8'
    LC_CTYPE 'C.UTF-8'
    TEMPLATE template0;
GRANT ALL PRIVILEGES ON DATABASE pangi_dev TO pangi_user;
\q

# Aplicar schema desde archivo local
psql -U pangi_user -h localhost -d pangi_dev -f 01_schema_pangi_dev.sql
```

Verificar:
```bash
psql -U pangi_user -h localhost -d pangi_dev -c "
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
# Debe mostrar 8 tablas

psql -U pangi_user -h localhost -d pangi_dev -c "
SELECT specialty, count(*) FROM knowledge_base GROUP BY specialty;"
# Debe mostrar: dental 12, plastic_surgery 10
```

### Paso 2 — N8N: Importar workflows

1. Acceder a N8N en el VPS GONEX
2. Settings → Credentials → Crear las 3 credenciales:
   - `Pangi DB (pangi_dev)` — Postgres → host: localhost, db: pangi_dev, user: pangi_user
   - `Evolution API - Pangi` — Header Auth → apikey: [API KEY de Evolution GONEX]
   - `Claude API - Pangi` — Header Auth → x-api-key: [API KEY de Anthropic]
3. Workflows → Import from file → importar en este orden:
   1. `05_db_manager.json`
   2. `04_handoff_manager.json`
   3. `01_nova.json`
   4. `02_sage.json`
   5. `03_atlas.json`
   6. `00_orchestrator.json`
4. Para cada workflow, vincular las credenciales a los nodos correspondientes
5. En `04_handoff_manager`, `02_sage`, `03_atlas` y `00_orchestrator`: vincular nodos `executeWorkflow` al ID de `05_db_manager` en la nueva instancia
6. En `00_orchestrator`: vincular nodos `executeWorkflow` de agentes a los IDs correctos de `01_nova`, `02_sage`, `03_atlas`
7. Activar **solo** `00_orchestrator`

> **Nota sobre IDs:** Los IDs de workflows en N8N son strings únicos generados por instancia. No se pueden transferir. Al importar en GONEX se generarán nuevos IDs — hay que re-vincular manualmente todos los `executeWorkflow`.

### Paso 3 — Evolution API: Configurar instancia Pangi

1. Acceder al Manager de Evolution API en GONEX
2. Crear nueva instancia: `Pangi-Produccion`
3. Conectar el número oficial de WhatsApp de Pangi
4. Configurar webhook:
   ```
   URL: https://[DOMINIO_N8N_GONEX]/webhook/pangi-whatsapp-dev
   Eventos: MESSAGES_UPSERT
   ```

### Paso 4 — Nginx: Configurar virtual hosts

Replicar el patrón de N8N de la cooperativa:

```nginx
server {
    server_name n8n.[DOMINIO_PANGI];
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    # SSL managed by Certbot
}
```

```bash
sudo certbot --nginx -d n8n.[DOMINIO_PANGI]
sudo certbot --nginx -d evolution.[DOMINIO_PANGI]
```

### Paso 5 — Verificación post-migración

Ejecutar pruebas funcionales con números de prueba antes de activar el número oficial:

```bash
# Test webhook directo
curl -X POST https://n8n.[DOMINIO_PANGI]/webhook/pangi-whatsapp-dev \
  -H "Content-Type: application/json" \
  -d '{
    "event": "messages.upsert",
    "instance": "Pangi-Produccion",
    "data": {
      "key": { "remoteJid": "51999000001@s.whatsapp.net", "fromMe": false, "id": "TEST001" },
      "message": { "conversation": "Hola" },
      "messageTimestamp": 1710500000,
      "pushName": "Test User"
    }
  }'
```

Verificar en DB:
```sql
SELECT u.phone, s.active_agent, ch.message
FROM users u
JOIN sessions s ON s.user_id = u.id
JOIN conversation_history ch ON ch.user_id = u.id
WHERE u.phone = '+51999000001'
ORDER BY ch.created_at;
```

### Paso 6 — Integración con DB de Pangi (coordinación con full stack)

Este paso requiere reunión con el desarrollador full stack de Pangi para:

1. **Identificar el motor de DB de Pangi** (PostgreSQL, MySQL, MongoDB u otro)
2. **Definir tablas relevantes:** pacientes, médicos, cotizaciones, citas
3. **Crear usuario de solo lectura** para el sistema de agentes:
   ```sql
   -- Ejemplo si es PostgreSQL
   CREATE USER pangi_agents_reader WITH PASSWORD '...';
   GRANT CONNECT ON DATABASE [pangi_production_db] TO pangi_agents_reader;
   GRANT SELECT ON TABLE patients, doctors, quotes, appointments TO pangi_agents_reader;
   ```
4. **Agregar credencial** en N8N para la DB de Pangi
5. **Agregar operación `getPatientHistory`** en `05_db_manager` que lea historial del paciente sin escribir nada (cumplimiento HIPAA)

---

## 11. Hoja de Ruta v2.0

### Prioridad Alta — Desbloquea el valor real del sistema

**1. Integración Claude API (NLU + NLG)**
Reemplazar keyword detection y respuestas hardcoded por Claude Haiku (NOVA) y Claude Sonnet (SAGE + ATLAS). El estado machine permanece — Claude solo reemplaza la lógica de interpretación y generación de texto. Impacto: comprensión natural del lenguaje, conversaciones más fluidas, manejo de casos edge.

**2. Integración DB Pangi (lectura)**
SAGE consulta historial médico del paciente en Pangi antes de hacer preguntas, evitando pedir información que ya tienen. ATLAS consulta cotizaciones reales de la plataforma. Requiere coordinación con full stack.

**3. Agendamiento real en NOVA**
NOVA conectada al sistema de citas de Pangi para mostrar disponibilidad real y confirmar citas. Requiere coordinación con full stack.

### Prioridad Media — Mejora la experiencia

**4. Soporte multilingüe (inglés + portugués)**
La arquitectura ya soporta `language` en la sesión. Solo requiere traducir los system prompts de Claude y los mensajes hardcoded del orquestador.

**5. Recepción de imágenes/documentos**
SAGE necesita que el paciente comparta radiografías y exámenes. Evolution API ya soporta recepción de imágenes — agregar manejo en el extractor y notificar a SAGE que el documento fue recibido.

**6. Botones interactivos de WhatsApp**
Reemplazar instrucciones de texto ("escribe 1 o 2") por botones nativos de WhatsApp para mejor UX. Evolution API V2 los soporta vía `sendButtons`.

### Prioridad Baja — Optimizaciones

**7. Dashboard de métricas**
Consultas de DB para el CEO de Pangi: volumen de conversaciones, tasa de completitud de SAGE, destinos más consultados en ATLAS, tiempo de respuesta promedio.

**8. Sistema de notificaciones**
Cuando un médico responde a una cotización en Pangi, notificar al paciente por WhatsApp con enlace.

**9. Expansión de especialidades**
Agregar procedimientos a la `knowledge_base`. Estructura ya definida — solo insertar filas nuevas y validar con médicos correspondientes.

---

## Apéndice — Estructura de Archivos del Proyecto

```
~/Documents/Projects/pangi-dev/
├── 01_schema_pangi_dev.sql     Schema completo de PostgreSQL
├── 02_migration_gonex.md       Este documento
│
├── workflows/                  Workflows de N8N (exportar desde UI)
│   ├── 05_db_manager.json
│   ├── 04_handoff_manager.json
│   ├── 00_orchestrator.json
│   ├── 01_nova.json
│   ├── 02_sage.json
│   └── 03_atlas.json
│
├── prompts/                    System prompts para Claude API (v2.0)
│   ├── nova_system_prompt.md
│   ├── sage_system_prompt.md
│   └── atlas_system_prompt.md
│
└── credentials_template.md    Estructura de credenciales (sin valores)
```

---

## Apéndice — Checklist de Entregables v1.0

| Entregable | Estado | Notas |
|------------|--------|-------|
| Schema PostgreSQL `pangi_dev` | ✅ Completo | 8 tablas, 22 procedimientos, 10 destinos |
| Base de conocimiento dental | ✅ Completo | 12 procedimientos — requiere validación médica |
| Base de conocimiento cirugía plástica | ✅ Completo | 10 procedimientos — requiere validación médica |
| Datos estáticos ATLAS | ✅ Completo | 10 destinos — costos estimados, actualizar con reales |
| Workflow `05_db_manager` | ✅ Completo | 18 operaciones, validación SQL, manejo de errores |
| Workflow `04_handoff_manager` | ✅ Completo | Warm transfer, 3 idiomas, auditoría en DB |
| Workflow `00_orchestrator` | ✅ Completo | 26 nodos, webhook activo, routing completo |
| Workflow `01_nova` | ✅ Completo | State machine, 7 estados |
| Workflow `02_sage` | ✅ Completo | State machine, 8 estados, score de completitud |
| Workflow `03_atlas` | ✅ Completo | Análisis de costo total, checklist pre-viaje |
| Integración Evolution API V2 | ✅ Completo | Webhook, sendText, manejo @lid |
| System prompts Claude | ⏳ Pendiente | Estructura definida, escritura en v2.0 |
| Número WhatsApp oficial Pangi | ⏳ Pendiente | Requiere el CEO de Pangi |
| Integración DB Pangi | ⏳ Pendiente | Requiere full stack Pangi |
| Deployment VPS GONEX | ⏳ Pendiente | Esta guía documenta el proceso |

---

*Documentación generada: 16 de Marzo del 2026*  
*Versión del sistema: 1.0.0*  
*Próxima revisión: Al inicio de v2.0*
