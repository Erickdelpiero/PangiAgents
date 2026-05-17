# Pangi — Sistema de Asistentes Inteligentes
## Documentación Técnica v2.0.0

**Proyecto:** NOVA · SAGE · ATLAS — Agentes de IA para Pangi  
**Autor:** Erick Del Piero Gonzales — Ing. Mecatrónico, Especialización en IA  
**Versión:** 2.0.0  
**Fecha:** 17 de Mayo del 2026  
**Estado:** MVP funcional con Claude API, LiteLLM, PHI Strip y Langfuse en VPS Cooperativa El Milagro  
**Pendiente:** Migración a VPS GONEX  

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Infraestructura — VPS Cooperativa El Milagro](#3-infraestructura--vps-cooperativa-el-milagro)
4. [Base de Datos PostgreSQL — pangi_dev](#4-base-de-datos-postgresql--pangi_dev)
5. [Workflows N8N](#5-workflows-n8n)
6. [Agentes — NOVA, SAGE y ATLAS](#6-agentes--nova-sage-y-atlas)
7. [Integración WhatsApp — Evolution API V2](#7-integración-whatsapp--evolution-api-v2)
8. [Bugs y Cambios v2.0](#8-bugs-y-cambios-v20)
9. [System Prompts — Claude API activo](#9-system-prompts--claude-api-activo)
10. [Guía de Migración a GONEX](#10-guía-de-migración-a-gonex)
11. [Hoja de Ruta post-MVP](#11-hoja-de-ruta-post-mvp)

---

## 1. Resumen Ejecutivo

### Qué es el sistema

Sistema de tres asistentes inteligentes integrados en WhatsApp para Pangi, plataforma de turismo médico. Los agentes atienden pacientes en español, inglés y portugués, guiándolos desde la orientación inicial hasta la elección del destino médico óptimo.

| Agente | Rol | Estado v2.0 |
|--------|-----|-------------|
| **NOVA** | Orientadora y gestora de citas | ✅ Funcional con Claude Haiku |
| **SAGE** | Especialista en cotizaciones médicas | ✅ Funcional con Claude Sonnet |
| **ATLAS** | Consejero de turismo médico | ✅ Funcional con Claude Sonnet |

### Qué hace v2.0 (cambios vs v1.0)

- **Claude API activa** — NLU en el orquestador y NLG en los tres agentes vía Claude Haiku (NOVA) y Claude Sonnet (SAGE, ATLAS)
- **LiteLLM proxy** — capa de abstracción de modelos; cambiar de Claude a GPT-4o o Gemini es una línea en config
- **PHI Strip** — Claude nunca recibe nombre ni teléfono del paciente; solo datos clínicos
- **Langfuse** — observabilidad completa: tokens, costo, estado, idioma por cada llamada Claude
- **Soporte trilingüe** — español, inglés y portugués con idioma persistente por sesión
- **22 procedimientos** con Q&A clínico real: coherencia semántica validada por Claude, escape mid-Q&A funcional

### Qué NO hace v2.0 (intencionalmente)

- No lee la base de datos de Pangi (requiere coordinación con el full stack de Pangi)
- No está integrado en la web de Pangi.com (requiere el widget de chat)
- No tiene el número de WhatsApp oficial de Pangi (usa instancia de prueba Test1)
- No tiene RAG (columna `embedding` en knowledge_base preparada pero vacía)

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
  • Extrae y valida mensaje
  • Crea o recupera usuario/sesión (PostgreSQL)
  • Guarda mensaje entrante
  • Router de intención (keywords + Claude NLU para casos ambiguos)
  • Switch → deriva a 01_nova / 02_sage / 03_atlas
  • Envía respuesta por WhatsApp vía Evolution API
  • Actualiza sesión y guarda mensaje saliente
       │
  ┌────┴────────────────┐
  ▼         ▼           ▼
01_nova   02_sage    03_atlas
  │           │           │
  │    [Motor → 🔐 Strip PHI → NLG Preparar → IF ¿NLG Activo?]
  │           │    TRUE → ☁️ LiteLLM proxy ──→ 📊 Langfuse
  │           │    FALSE → skip              │
  │           │           └──────────────────┘
  │           │                    ↓
  └─────┬─────┘             Procesar NLG
        ▼
   05_db_manager
   (todas las operaciones DB)
        │
        ▼
   PostgreSQL 16
   pangi_dev
```

### Capa LiteLLM

```
N8N (http://127.0.0.1:4000/v1/messages)
       │
       ▼
LiteLLM proxy (puerto 4000, localhost only)
  • Acepta Anthropic-format requests
  • Enruta: claude-sonnet-4-20250514 → Anthropic API
  • Enruta: claude-haiku-4-5-20251001 → Anthropic API
  • API key de Anthropic vive SOLO en /var/www/litellm/.env
  • Modelo alternativo futuro: cambiar una línea en config.yaml
       │
       ▼
api.anthropic.com
```

### Capa PHI Strip

```
Motor → 🔐 Strip PHI → NLG Preparar → ☁️ Claude
          │                │
          ├── ...inp        ├── motor = raw._phi_clean
          │   (full data)   │   (sin userName, sin phone)
          ├── phi_stripped  └── return usa ...raw
          └── _phi_clean        (preserva remoteJid para WhatsApp)
              (sin PHI)
```

### Patrón de contexto de sesión

El contexto de sesión es un objeto JSON almacenado en `sessions.context`. Cada agente tiene su propio namespace:

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
  },
  "language": "es"
}
```

---

## 3. Infraestructura — VPS Cooperativa El Milagro

### Especificaciones del servidor

```
Proveedor:  Contabo
OS:         Ubuntu 24.04.3 LTS
RAM:        8 GB
Disco:      72 GB SSD (~16 GB usados)
CPU:        3 vCores
Hostname:   vmi2857037
```

### Acceso SSH

```bash
ssh VPS-Contabo
# o directamente:
ssh erick_user@[IP_VPS]
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
│   ├── PostgreSQL 16      → pangi_dev       → puerto 5432 (localhost)
│   ├── N8N v1.116+        → /var/www/n8n/   → puerto 5678
│   ├── Evolution API V2   → /var/www/evolution-api/ → puerto 8080
│   └── LiteLLM 1.84.0     → /var/www/litellm/ → puerto 4000 (localhost only)
│
└── NGINX (reverse proxy compartido)
    ├── coopelmilagro.com      → Gunicorn (cooperativa)
    ├── n8n.coopelmilagro.com  → localhost:5678 (N8N)
    └── evolution.coopelmilagro.com → localhost:8080 (Evolution API)
    # Puerto 4000 (LiteLLM) NO expuesto via nginx — solo acceso interno
```

### N8N — configuración relevante

```
Versión:    1.116+ (npm, no Docker)
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

### LiteLLM — configuración relevante *(nuevo en v2.0)*

```
Versión:    1.84.0 (Python venv, no Docker)
Instalación: /var/www/litellm/
Venv:       /var/www/litellm/venv/
Servicio:   systemd (litellm.service)
Usuario:    litellm_user (uid=999, sin shell)
Puerto:     4000 (solo localhost — no expuesto)
Config:     /var/www/litellm/config.yaml
API Key:    /var/www/litellm/.env (chmod 600)
```

`/var/www/litellm/config.yaml`:
```yaml
model_list:
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY

litellm_settings:
  drop_params: true
  set_verbose: false
```

Comandos de control:
```bash
sudo systemctl status litellm
sudo systemctl restart litellm
sudo journalctl -u litellm -f --no-pager | grep -E "POST|ERROR|200|400"
```

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

### Firewall (UFW)

```
Puertos abiertos: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5678 (N8N directo)
Puerto 4000 (LiteLLM): NO abierto externamente — solo acceso interno
```

---

## 4. Base de Datos PostgreSQL — pangi_dev

*(Sin cambios respecto a v1.0 — ver sección completa en el documento original)*

### Conexión

```bash
psql -U pangi_user -h localhost -d pangi_dev
```

### Esquema — 8 tablas

`users`, `sessions`, `conversation_history`, `medical_intake`, `quotes_comparison`, `atlas_destinations`, `knowledge_base`, `agent_handoffs`

Schema completo en `01_schema_pangi_dev.sql`.

**22 procedimientos cargados:** 12 dentales + 10 cirugía plástica.  
**10 destinos ATLAS:** México, Colombia, Perú, Costa Rica, Argentina, Rep. Dominicana, USA (referencia).

> **Preparación para RAG (pendiente activar):** la columna `embedding vector(1536)` se agregará en el Paso 5 de GONEX. La estructura está lista; el interruptor no está encendido.

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

### Credenciales en N8N *(actualizado en v2.0)*

| Nombre | Tipo | Uso |
|--------|------|-----|
| `Pangi DB (pangi_dev)` | Postgres | `05_db_manager` |
| `Evolution API - Pangi` | Header Auth (`apikey`) | `00_orchestrator` |
| `Claude API - Pangi` | Header Auth (`x-api-key`) | Credencial existente; la key activa está en LiteLLM — N8N puede tener la misma key o una placeholder, LiteLLM no la valida |
| `Langfuse — Pangi` | Basic Auth (pk/sk) | Nodos Langfuse en agentes |

> **Nota importante:** Al migrar a GONEX, las credenciales no se exportan en los JSONs por seguridad. Recrear manualmente y re-vincular. La API key de Anthropic va en `/var/www/litellm/.env` de GONEX — no en N8N.

### Nodos nuevos en v2.0 por agente

Cada agente (`01_nova`, `02_sage`, `03_atlas`) incorpora:

| Nodo | Posición | Función |
|------|----------|---------|
| `🔐 Strip PHI` | Entre Motor y NLG Preparar | Elimina userName, userPhone del contexto Claude |
| `✅ ¿NLG Activo?` | Entre NLG Preparar y Claude HTTP | Evita llamadas a LiteLLM cuando `_nlgSkip: true` |
| `📊 Langfuse — [AGENTE]` | Rama paralela desde Claude HTTP | Prepara trace payload |
| `📤 Langfuse — Enviar ([AGENTE])` | Después del Code de Langfuse | Envía trace a us.cloud.langfuse.com |

### URLs de Claude en N8N *(actualizado en v2.0)*

Todos los nodos Claude apuntan a LiteLLM, no directamente a Anthropic:
```
http://127.0.0.1:4000/v1/messages
```

---

## 6. Agentes — NOVA, SAGE y ATLAS

### NOVA — Orientadora *(actualizado v2.0)*

**Archivo:** `01_nova.json`

Claude Haiku genera los mensajes de handoff y fallback cuando `claudeSkip=false`. El routing y estado machine permanece en el motor — Claude solo genera el texto natural de transición.

Estados: `welcome`, `initial_presented`, `gathering_appointment_city`, `gathering_appointment_specialty`, `handoff_complete`, `active`, `clarification_needed`

### SAGE — Especialista en Cotizaciones *(actualizado v2.0)*

**Archivo:** `02_sage.json`

Claude Sonnet valida coherencia semántica en el Q&A, extrae datos clínicos limpios, detecta escape intents, y genera respuestas naturales multilingüe. El state machine permanece — Claude opera como capa de NLU/NLG sobre la estructura existente.

**Cambios clave v2.0:**
- Validación de coherencia: si `isCoherent=false` y no hay escape intent, rollback automático de `collected_data` y `current_q_index`
- Escape mid-Q&A: `change_procedure` limpia estado y reinicia; `go_atlas` transfiere con contexto
- Idioma persistente: detectado en primer mensaje, almacenado en `sessions.context.language`
- PHI Strip: `fn = null` en NLG Preparar — Claude no recibe el nombre del paciente

Estados: `handoff_received`, `selecting_specialty`, `procedure_confirmed`, `gathering_profile`, `questioning`, `summary`, `complete`, `handoff_to_atlas`

### ATLAS — Consejero de Turismo Médico *(actualizado v2.0)*

**Archivo:** `03_atlas.json`

Claude Sonnet enriquece el análisis de destinos con narrativa personalizada. El cálculo de costos sigue siendo determinístico en el motor.

**Cambios clave v2.0:**
- Sin default `'dental'` hardcodeado — cuando no hay procedimiento, Claude genera análisis genérico
- `recoveryField` usa dental como default seguro cuando `procType` es vacío
- Parser de cotizaciones con `pending_dest`/`pending_price` para ingreso conversacional

Estados: `welcome`, `handoff_received`, `has_quotes_check`, `exploring`, `entering_quotes`, `analyzing`, `comparison_done`, `checklist_shown`

---

## 7. Integración WhatsApp — Evolution API V2

*(Sin cambios respecto a v1.0)*

```
Manager: https://evolution.coopelmilagro.com/manager
Instancia: Test1
Webhook: https://n8n.coopelmilagro.com/webhook/pangi-whatsapp-dev
```

---

## 8. Bugs y Cambios v2.0

### Resueltos en v1.0 (histórico)

| Bug | Fix |
|-----|-----|
| Sesiones múltiples por usuario | `UNIQUE INDEX` parcial + CTE en createSession |
| IF siempre va al FALSE path | Valor `0` explícito en Right value |
| sessionId NaN en agentes | Code nodes preparadores antes de executeWorkflow |
| remoteJid null en Evolution API | Prioridad a `remoteJidAlt` en extractor |
| ATLAS no acepta cotizaciones desde `exploring` | Parser añadido en estado `exploring` |
| `alwaysOutputData` causa count:1 con 0 filas | Filtro positivo por campos de filas reales |

### Resueltos en v2.0

| Bug | Fix |
|-----|-----|
| SAGE acepta cualquier texto como respuesta válida | Validación `isCoherent` en Claude + rollback de `current_q_index` |
| Cambio de procedimiento mid-Q&A sin limpiar estado | Bloques `change_procedure`/`abort` en Procesar NLG SAGE |
| Idioma detectado por mensaje (no por sesión) | Fix en `Normalizar — Sesión Existente` + Merge Handoff Result NOVA |
| ATLAS asume procedimiento dental sin contexto | `procType` sin default `'dental'`; `recoveryField` lógica corregida |
| Error 400 LiteLLM cuando `_nlgSkip: true` | Nodos IF `¿NLG Activo?` en los 3 agentes |
| `remoteJid: null` en Evolution API por PHI Strip | Todos los `return` en NLG Preparar usan `...raw` (no `...motor`) |
| ATLAS `destMatch` solo buscaba ciudad si había precio | `destMatch` desacoplado de `price` en estado `exploring` |

### Pendientes post-MVP

| Pendiente | Prioridad |
|-----------|-----------|
| Integración DB Pangi (lectura historial paciente) | Alta |
| Agendamiento real en NOVA | Alta |
| Cotizaciones reales desde DB Pangi en ATLAS | Alta |
| Validación médica de la knowledge_base | Alta |
| Número WhatsApp oficial Pangi | Alta |
| Botones interactivos nativos de WhatsApp | Media |
| Recepción de imágenes/radiografías en SAGE | Media |
| RAG sobre knowledge_base (columna embedding lista) | Baja |

---

## 9. System Prompts — Claude API activo

Los prompts viven en `/prompts/` del proyecto como fuente de verdad. Los nodos NLG Preparar de cada agente los tienen inline como copia operativa. Cualquier cambio empieza en el `.md` y luego se copia al nodo N8N correspondiente.

```
~/Documents/Projects/pangi-dev/prompts/
├── README.md                   Convenciones de versiones y flujo de cambio
├── sage_system_base.md         Identidad base + política PHI
├── sage_questioning.md         Q&A con validación coherencia (estado: questioning)
├── sage_handoff_received.md    Detección de procedimiento
├── sage_procedure_confirmed.md Traducción Q1 para EN/PT
├── sage_summary.md             Resumen de expediente
├── atlas_nlg.md                Análisis de destinos (todos los estados)
└── nova_nlg.md                 Mensajes de handoff y fallback
```

### Endpoints Claude en v2.0

```
Endpoint (vía LiteLLM): http://127.0.0.1:4000/v1/messages
Modelos activos:
  - claude-haiku-4-5-20251001  → NOVA (velocidad)
  - claude-sonnet-4-20250514   → SAGE + ATLAS (capacidad clínica)
```

### Costo operativo real (medido en Langfuse)

| Componente | Costo estimado/mes (uso moderado) |
|------------|----------------------------------|
| Claude Haiku (NOVA) | ~$2-5 USD |
| Claude Sonnet (SAGE + ATLAS) | ~$10-25 USD |
| LiteLLM + N8N + Evolution API | $0 (self-hosted) |
| PostgreSQL | $0 (incluido en VPS) |
| Langfuse Cloud (hobby) | $0 |
| **Total estimado** | **~$12-30 USD/mes** |

---

## 10. Guía de Migración a GONEX

### Pre-requisitos en VPS GONEX

- [ ] Ubuntu 24.04 LTS con Docker y Docker Compose instalados
- [ ] PostgreSQL 16+ instalado y corriendo
- [ ] N8N instalado (mismo método que VPS cooperativa — npm/systemd)
- [ ] Evolution API V2 instalado
- [ ] Nginx con SSL (Let's Encrypt)
- [ ] Dominio de Pangi apuntando al VPS GONEX

### Paso 1 — PostgreSQL: Crear base de datos

```bash
sudo -u postgres psql

CREATE USER pangi_user WITH PASSWORD 'NUEVA_PASSWORD_SEGURA';
CREATE DATABASE pangi_dev
    WITH OWNER pangi_user ENCODING 'UTF8'
    LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;
GRANT ALL PRIVILEGES ON DATABASE pangi_dev TO pangi_user;
\q

psql -U pangi_user -h localhost -d pangi_dev -f 01_schema_pangi_dev.sql
```

Verificar:
```bash
psql -U pangi_user -h localhost -d pangi_dev -c \
  "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
# Debe mostrar 8 tablas

psql -U pangi_user -h localhost -d pangi_dev -c \
  "SELECT specialty, count(*) FROM knowledge_base GROUP BY specialty;"
# dental 12, plastic_surgery 10
```

### Paso 2 — LiteLLM: Desplegar con Docker *(nuevo en v2.0)*

En GONEX, LiteLLM corre en Docker (a diferencia del VPS actual donde es nativo).

Crear directorio y archivos de configuración:
```bash
mkdir -p /var/www/litellm
```

`/var/www/litellm/config.yaml`:
```yaml
model_list:
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY

litellm_settings:
  drop_params: true
  set_verbose: false
```

`/var/www/litellm/.env` (chmod 600):
```
ANTHROPIC_API_KEY=sk-ant-api03-TU_KEY
```

`/var/www/litellm/docker-compose.yml`:
```yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    ports:
      - "127.0.0.1:4000:4000"
    volumes:
      - ./config.yaml:/app/config.yaml
    env_file: .env
    command: --config /app/config.yaml --port 4000
    restart: unless-stopped
```

```bash
cd /var/www/litellm
docker compose up -d
curl -s http://127.0.0.1:4000/v1/models | python3 -m json.tool
# Debe mostrar los 2 modelos Claude
```

> **Nota de URL para N8N en GONEX:** si N8N también corre en Docker en la misma red, usar `http://litellm:4000/v1/messages`. Si N8N es nativo (systemd), usar `http://127.0.0.1:4000/v1/messages` — igual que el VPS actual.

### Paso 3 — N8N: Importar workflows y credenciales

1. Acceder a N8N en VPS GONEX
2. **Settings → Credentials → Crear las siguientes credenciales:**

| Nombre | Tipo | Valor |
|--------|------|-------|
| `Pangi DB (pangi_dev)` | Postgres | host: localhost, db: pangi_dev, user: pangi_user |
| `Evolution API - Pangi` | Header Auth (`apikey`) | API KEY de Evolution GONEX |
| `Claude API - Pangi` | Header Auth (`x-api-key`) | Cualquier valor — LiteLLM no la valida en este setup |
| `Langfuse — Pangi` | Basic Auth | User: pk-lf-..., Password: sk-lf-... |

3. **Workflows → Import from file → importar en este orden:**
   1. `05_db_manager.json`
   2. `04_handoff_manager.json`
   3. `01_nova.json`
   4. `02_sage.json`
   5. `03_atlas.json`
   6. `00_orchestrator.json`

4. Re-vincular credenciales y sub-workflows (los IDs cambian al reimportar)
5. Activar **solo** `00_orchestrator`

> **Nota sobre IDs:** Al importar en GONEX se generan nuevos IDs — re-vincular manualmente todos los nodos `executeWorkflow`.

### Paso 4 — Evolution API: Configurar instancia Pangi

1. Acceder al Manager en GONEX
2. Crear instancia: `Pangi-Produccion`
3. Conectar el número oficial de WhatsApp de Pangi
4. Configurar webhook:
   ```
   URL: https://[DOMINIO_N8N_GONEX]/webhook/pangi-whatsapp-dev
   Eventos: MESSAGES_UPSERT
   ```

### Paso 5 — Nginx: Configurar virtual hosts

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
}
```

```bash
sudo certbot --nginx -d n8n.[DOMINIO_PANGI]
sudo certbot --nginx -d evolution.[DOMINIO_PANGI]
```

### Paso 6 — Verificación post-migración

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

Verificar trazas en Langfuse (`us.cloud.langfuse.com`) y DB:
```sql
SELECT u.phone, s.active_agent, ch.message
FROM users u
JOIN sessions s ON s.user_id = u.id
JOIN conversation_history ch ON ch.user_id = u.id
WHERE u.phone = '+51999000001'
ORDER BY ch.created_at;
```

### Paso 7 — Integración con DB de Pangi (coordinación con full stack)

Requiere reunión con el desarrollador full stack de Pangi para definir acceso de lectura a tablas de pacientes, médicos y cotizaciones.

---

## 11. Hoja de Ruta post-MVP

### Prioridad Alta — Desbloquea el valor real del sistema

**1. Integración DB Pangi (lectura)**
SAGE consulta historial médico del paciente en Pangi antes de hacer preguntas. ATLAS consulta cotizaciones reales. Requiere coordinación con full stack.

**2. Agendamiento real en NOVA**
NOVA conectada al sistema de citas de Pangi para mostrar disponibilidad real y confirmar citas.

**3. Número WhatsApp oficial Pangi**
Cambiar de instancia `Test1` a la instancia de producción con el número oficial.

**4. Validación médica de knowledge_base**
Los 22 procedimientos fueron construidos con estándares clínicos generales. Requieren revisión y aprobación de los médicos de Pangi antes de producción.

### Prioridad Media — Mejora la experiencia

**5. Recepción de imágenes/documentos**
SAGE necesita recibir radiografías y exámenes. Evolution API V2 ya soporta recepción de imágenes.

**6. Botones interactivos de WhatsApp**
Reemplazar instrucciones de texto por botones nativos de WhatsApp. Evolution API V2 los soporta.

**7. LangGraph (antes de Azure)**
Sistema de agentes en Python con LangGraph y FastAPI. N8N queda solo para webhooks. Los prompts de `/prompts/*.md` se convierten en system prompt files que Python lee directamente.

### Prioridad Baja — Optimizaciones

**8. RAG sobre knowledge_base**
La columna `embedding vector(1536)` está preparada en el schema. Cuando llegue el momento, un script de embeddings la llena y el sistema hace búsqueda semántica sin cambios estructurales.

**9. Langfuse self-hosted en Azure**
Al migrar a Azure, Langfuse corre self-hosted con imagen Docker oficial. Solo cambia la URL del endpoint — cero cambio de lógica en N8N o LangGraph.

---

## Apéndice — Estructura de Archivos del Proyecto

```
~/Documents/Projects/pangi-dev/
├── 01_schema_pangi_dev.sql     Schema completo de PostgreSQL (8 tablas)
├── 02_migration_gonex.md       Este documento (v2.0.0)
├── 03_kb_migration_v1.1.0.sql  Migración de knowledge_base
├── Roadmap detallado MVP.md    Estado de los 5 pasos del MVP
│
├── workflows/                  Workflows N8N exportados (v2.0)
│   ├── 05_db_manager.json
│   ├── 04_handoff_manager.json
│   ├── 00_orchestrator.json
│   ├── 01_nova.json            Incluye Strip PHI, IF NLG, Langfuse
│   ├── 02_sage.json            Incluye Strip PHI, IF NLG, Langfuse
│   └── 03_atlas.json           Incluye Strip PHI, IF NLG, Langfuse
│
└── prompts/                    System prompts Claude API (fuente de verdad)
    ├── README.md
    ├── sage_system_base.md
    ├── sage_questioning.md
    ├── sage_handoff_received.md
    ├── sage_procedure_confirmed.md
    ├── sage_summary.md
    ├── atlas_nlg.md
    └── nova_nlg.md
```

---

## Apéndice — Checklist de Entregables v2.0

| Entregable | Estado | Notas |
|------------|--------|-------|
| Schema PostgreSQL `pangi_dev` | ✅ Completo | 8 tablas, 22 procedimientos, 10 destinos |
| Base de conocimiento dental | ✅ Completo | 12 procedimientos — requiere validación médica |
| Base de conocimiento cirugía plástica | ✅ Completo | 10 procedimientos — requiere validación médica |
| Datos estáticos ATLAS | ✅ Completo | 10 destinos — costos estimados, actualizar con reales |
| Workflow `05_db_manager` | ✅ Completo | 18 operaciones |
| Workflow `04_handoff_manager` | ✅ Completo | Warm transfer trilingüe, auditoría en DB |
| Workflow `00_orchestrator` | ✅ Completo | Webhook activo, routing + Claude NLU |
| Workflow `01_nova` | ✅ Completo | Claude Haiku, PHI Strip, Langfuse |
| Workflow `02_sage` | ✅ Completo | Claude Sonnet, PHI Strip, Q&A coherente, Langfuse |
| Workflow `03_atlas` | ✅ Completo | Claude Sonnet, PHI Strip, análisis costo total, Langfuse |
| Claude API (NLU + NLG) | ✅ Completo | Haiku para NOVA, Sonnet para SAGE/ATLAS |
| LiteLLM proxy | ✅ Completo | Nativo en VPS actual, Docker en GONEX |
| PHI Strip | ✅ Completo | `_phi_clean` en 3 agentes, `phi_stripped: true` auditado |
| Langfuse observabilidad | ✅ Completo | us.cloud.langfuse.com, proyecto pangi-dev |
| Soporte multilingüe ES/EN/PT | ✅ Completo | Idioma persistente por sesión |
| System prompts documentados | ✅ Completo | `/prompts/` — 7 archivos .md |
| Integración Evolution API V2 | ✅ Completo | Webhook, sendText, manejo @lid |
| Número WhatsApp oficial Pangi | ⏳ Pendiente | Requiere el CEO de Pangi |
| Integración DB Pangi | ⏳ Pendiente | Requiere full stack Pangi |
| Deployment VPS GONEX | ⏳ Pendiente | Esta guía documenta el proceso |

---

*Documentación generada: 17 de Mayo del 2026*  
*Versión del sistema: 2.0.0*  
*Próxima revisión: Al completar migración a GONEX (Paso 5)*