# Roadmap detallado — MVP GONEX

---

### PASO 1 — Cerrar los 4 issues de V2 ✅ COMPLETADO
**Objetivo:** conversaciones que se sienten naturales, no predefinidas.

**Qué se resolvió:**

*Issue 1 — Coherencia SAGE.* Implementado rollback en `🔧 Procesar — NLG SAGE`: cuando `isCoherent=false` y no hay escape intent, revierte `collected_data` y decrementa `current_q_index`. Claude repregunta en lugar de avanzar con dato inválido.

*Issue 2 — Cambio de procedimiento mid-Q&A.* Bloques `change_procedure` y `abort` en Procesar NLG SAGE. Resetea `sage.state='procedure_confirmed'`, `collected_data={}`, `current_q_index=1`. El flujo reinicia limpio desde la confirmación del nuevo procedimiento.

*Issue 3 — Idioma por sesión.* Fix en `🔧 Normalizar — Sesión Existente` del orquestador: `userLanguage: sessionContext.language || userData.language || 'es'`. Fix adicional en `🔧 Merge Handoff Result` de NOVA para propagar el idioma al contexto de sesión.

*Issue 4 — ATLAS sin cotizaciones.* `procType` ya no usa `'dental'` como fallback hardcodeado — usa `''`. `recoveryField` usa `plastic_surgery` como único condicional explícito, con dental como default. Claude recibe contexto genérico cuando no hay procedimiento definido.

**Archivos modificados:** `02_sage.json`, `03_atlas.json`, `00_orchestrator.json`, `01_nova.json`

---

### PASO 2 — Capa de de-identificación PHI ✅ COMPLETADO
**Objetivo:** Claude nunca recibe identificadores personales del paciente.

**Qué se construyó:** Nodo Code dedicado `🔐 Strip PHI` en cada agente (SAGE, ATLAS, NOVA), insertado entre el Motor y el NLG Preparar. El nodo preserva todos los datos en el payload principal (`...inp`) para que los nodos downstream (WhatsApp, DB) funcionen normalmente. Agrega `_phi_clean` con solo datos clínicos y `phi_stripped: true` como flag de auditoría.

Los nodos NLG Preparar usan `raw._phi_clean || raw` para construir los prompts de Claude. Los returns de todos los nodos usan `...raw` (no `...motor`) para preservar `remoteJid` y `userName` en el flujo hacia `📤 Construir Respuesta Final`.

Todos los prompts exportados a `/prompts/` como fuente de verdad documentada.

**Archivos modificados:** `01_nova.json`, `02_sage.json`, `03_atlas.json`

---

### PASO 3 — LiteLLM como proxy de modelos ✅ COMPLETADO
**Objetivo:** el sistema es model-agnostic desde hoy.

**Qué se construyó:** LiteLLM 1.84.0 instalado de forma **nativa** (no Docker) en el VPS actual usando Python 3.12 venv, bajo usuario dedicado `litellm_user`, corriendo como servicio systemd en `127.0.0.1:4000`.

> **Nota de diferencia vs plan original:** el roadmap contemplaba Docker en GONEX. Dado que aún operamos en el VPS de Cooperativa El Milagro, se instaló nativo para consistencia con el entorno actual. Al migrar a GONEX, LiteLLM correrá en Docker (ver sección LiteLLM en `02_migration_gonex.md`).

Los 4 nodos HTTP de N8N (`☁️ Claude NLU — Haiku`, `☁️ Claude NLG — NOVA Haiku`, `☁️ Claude NLG — SAGE Sonnet`, `☁️ Claude NLG — ATLAS Sonnet`) redirigidos de `https://api.anthropic.com/v1/messages` a `http://127.0.0.1:4000/v1/messages`. La API key de Anthropic vive solo en `/var/www/litellm/.env`.

Se agregaron nodos IF `✅ ¿NLG Activo?` en los 3 agentes para evitar llamadas a LiteLLM cuando `_nlgSkip: true`, eliminando errores 400 por payloads vacíos.

**Archivos modificados:** `01_nova.json`, `02_sage.json`, `03_atlas.json`  
**Archivos VPS creados:** `/var/www/litellm/config.yaml`, `/var/www/litellm/.env`, `/etc/systemd/system/litellm.service`

---

### PASO 4 — Langfuse para observabilidad ✅ COMPLETADO
**Objetivo:** visibilidad completa de cada decisión del sistema. Dashboard funcional para mostrar a el CEO de Pangi.

**Qué se construyó:** Cuenta Langfuse Cloud en región US (`us.cloud.langfuse.com`), proyecto `pangi-dev`. En cada agente se agregó una rama paralela desde el nodo Claude HTTP: nodo Code `📊 Langfuse — [AGENTE]` + nodo HTTP `📤 Langfuse — Enviar ([AGENTE])`. Solo se traza cuando Claude efectivamente corrió (rama paralela garantiza esto).

Cada trace incluye: `session_id`, `agent`, `state/action`, `language`, `input_tokens`, `output_tokens`, `cost_usd`, `phi_stripped`. El batch envía `trace-create` + `generation-create` en una sola llamada para que el trace padre exista antes que la generación.

Credencial `Langfuse — Pangi` (Basic Auth) creada en N8N.

> **Nota sobre producción:** al migrar a Azure, Langfuse corre self-hosted. Solo cambia la URL del endpoint — cero cambio de lógica en N8N o LangGraph.

**Archivos modificados:** `01_nova.json`, `02_sage.json`, `03_atlas.json`

---

### PASO 5 — GONEX migration + Supabase prep + documentación final ⏳ PENDIENTE
**Objetivo:** sistema limpio, documentado y listo para la demo. Base preparada para RAG sin activarlo aún.

**Qué se hace:**

Migración completa al VPS GONEX siguiendo `02_migration_gonex.md` (v2.0.0), que incorpora todos los cambios de los pasos 1-4.

Preparación del schema para RAG (sin activar):
```sql
ALTER TABLE knowledge_base ADD COLUMN embedding vector(1536);
CREATE INDEX ON knowledge_base USING ivfflat (embedding vector_cosine_ops);
```

**Entregable:** sistema completo corriendo en GONEX con LiteLLM en Docker, observabilidad activa en Langfuse, schema preparado para RAG. Demo lista para el CEO de Pangi.

**Estimado:** 1 sesión.

---

### POST-MVP — LangGraph en GONEX (antes de Azure)
Después de la demo a el CEO de Pangi. Sistema de agentes reconstruido en Python con LangGraph y FastAPI. N8N queda solo para manejo de webhooks de WhatsApp y notificaciones externas. Los prompts (`/prompts/*.md`), la knowledge base y el diseño de agentes se transfieren directamente. Cuando Azure esté disponible, este código va ahí sin cambios estructurales.