## Roadmap detallado — MVP GONEX

---

### PASO 1 — Cerrar los 4 issues de V2
**Objetivo:** conversaciones que se sienten naturales, no predefinidas.

**Qué se resuelve:**

*Issue 1 — SAGE acepta cualquier texto como respuesta válida.* Claude Sonnet debe validar coherencia semántica antes de guardar el dato. Si el usuario escribe "hola" cuando SAGE pregunta cuántos implantes necesita, Claude detecta la incoherencia y repregunta con contexto. Se implementa como una validación dentro del motor de SAGE antes del `updateSession`.

*Issue 2 — Cambio de procedimiento mid-Q&A.* Cuando `escapeIntent` es true dentro del estado `questioning`, el state machine debe limpiar `collected_data`, resetear `current_q_index` a 0 y reiniciar desde `procedure_confirmed` con el nuevo procedimiento. Actualmente el escape sale del flujo pero no limpia el estado correctamente.

*Issue 3 — Idioma por sesión, no por mensaje.* El idioma se fija en `sessions.context.language` en el primer mensaje y se inyecta como override en todos los system prompts de Claude. Si `context.language` ya existe, no se detecta de nuevo. Aplica a los tres agentes y al orchestrator.

*Issue 4 — ATLAS sin cotizaciones.* Cuando `atlas.quotes` está vacío o no existe, Claude genera una respuesta que orienta al usuario hacia SAGE primero, en lugar de mostrar un análisis vacío o un mensaje de error. Se maneja en el system prompt de ATLAS con una instrucción explícita para este caso.

**Archivos necesarios:** `02_sage.json`, `03_atlas.json`, `00_orchestrator.json` — los compartes al iniciar este paso.

**Entregable:** tres workflows actualizados listos para importar. Conversaciones naturales sin los 4 problemas identificados.

**Estimado:** 1-2 sesiones de trabajo.

---

### PASO 2 — Capa de de-identificación PHI
**Objetivo:** Claude nunca recibe identificadores personales del paciente.

**Qué se construye:** una función `stripPHI()` que se ejecuta como nodo Code en cada agente, entre el paso de "leer sesión" y el paso de "llamar a Claude". La función extrae del contexto de sesión únicamente los datos clínicos que Claude necesita para hacer su trabajo, descartando `user_phone`, `user_name`, y cualquier referencia directa al usuario. La respuesta de Claude se recibe limpia y se re-integra al contexto completo.

El `05_db_manager` también recibe un ajuste: cuando prepara el payload para pasar al agente, incluye un campo `phi_stripped: true` que sirve como flag de auditoría para Langfuse en el paso siguiente.

**Archivos necesarios:** ninguno previo. Te comparto los nodos Code nuevos para insertar en cada workflow.

**Entregable:** los tres agentes actualizados con la capa PHI activa. Verificable directamente en los logs de Claude API — los payloads ya no contienen datos del usuario.

**Estimado:** 1 sesión.

---

### PASO 3 — LiteLLM como proxy de modelos
**Objetivo:** el sistema es model-agnostic desde hoy.

**Qué se construye:** LiteLLM se instala en Docker en GONEX con un `docker-compose.yml` mínimo. Se configura con Claude Sonnet y Haiku como modelos por defecto. Los 4 nodos HTTP que actualmente apuntan a `api.anthropic.com` se redirigen a `http://localhost:4000`, que es donde corre LiteLLM. La API key de Anthropic se mueve del nodo N8N al archivo de configuración de LiteLLM.

El resultado funcional: el sistema opera exactamente igual. El resultado estratégico: para probar GPT-4o o Gemini en SAGE se cambia una línea en la config de LiteLLM, sin tocar ningún workflow.

Como bonus, LiteLLM expone métricas nativas de uso y costo por modelo que se integran fácilmente con Langfuse en el paso siguiente.

**Archivos necesarios:** ninguno de tu parte. Te entrego el `docker-compose.yml` y las instrucciones de instalación en GONEX.

**Entregable:** LiteLLM corriendo en GONEX, 4 nodos N8N actualizados, verificación de que una conversación completa funciona a través del proxy.

**Estimado:** 1 sesión.

---

### PASO 4 — Langfuse para observabilidad
**Objetivo:** visibilidad completa de cada decisión del sistema. Dashboard funcional para mostrar a el CEO de Pangi.

**Qué se construye:** se crea una cuenta en Langfuse Cloud (gratuita, sin infraestructura). Se agregan cuatro nodos HTTP en N8N, uno por cada llamada Claude, que envían un trace a Langfuse con: `session_id`, `agent_name`, `state`, `language`, `tokens_used`, `latency_ms`, y `cost_usd`. El `phi_stripped: true` del paso anterior va como metadata de auditoría.

El dashboard de Langfuse queda con: conversaciones trazadas en tiempo real, costo diario por agente, latencia promedio por estado, y tasa de éxito de las llamadas Claude.

Nota sobre producción futura: cuando el sistema migre a Azure, Langfuse se despliega self-hosted dentro de la infraestructura de Pangi con imagen Docker oficial. El código de integración en N8N o LangGraph es idéntico, solo cambia la URL del endpoint de `cloud.langfuse.com` a la instancia interna. Cero cambio de lógica.

**Archivos necesarios:** ninguno.

**Entregable:** Langfuse conectado, dashboard mostrando conversaciones reales. Screenshot o grabación de pantalla para incluir en la demo a el CEO de Pangi.

**Estimado:** 1 sesión.

---

### PASO 5 — GONEX migration + Supabase prep + documentación final
**Objetivo:** sistema limpio, documentado y listo para la demo. Base preparada para RAG sin activarlo aún.

**Qué se hace:**

Primero, si el sistema no está aún en GONEX, se aplica el proceso de migración del `02_migration_gonex_v2.md` ya generado, con los ajustes de los pasos 1-4 incorporados.

Segundo, se agrega la columna vector a la tabla `knowledge_base` en PostgreSQL:

```sql
ALTER TABLE knowledge_base ADD COLUMN embedding vector(1536);
CREATE INDEX ON knowledge_base USING ivfflat (embedding vector_cosine_ops);
```

La columna queda vacía. Cuando llegue el momento de activar RAG, un script de embeddings la llena y el sistema empieza a hacer búsqueda semántica sin ningún otro cambio estructural. La preparación está hecha, el interruptor no está encendido.

Tercero, se actualiza la documentación del proyecto: `02_migration_gonex_v2.md` incorpora los cambios de todos los pasos, el stack actualizado con LiteLLM y Langfuse, y una sección nueva de roadmap post-MVP que documenta el path a LangGraph y Azure.

**Entregable:** sistema completo corriendo en GONEX con observabilidad activa, esquema preparado para RAG, documentación actualizada. Demo lista para el CEO de Pangi.

**Estimado:** 1 sesión.

---

### POST-MVP — LangGraph en GONEX (antes de Azure)
Este paso ocurre después de la demo a el CEO de Pangi, no es parte del MVP pero es parte del roadmap completo. Se construye el sistema de agentes en Python con LangGraph y FastAPI. N8N queda solo para manejo de webhooks de WhatsApp y notificaciones externas. Los prompts, la knowledge base y el diseño de agentes se transfieren directamente. Cuando Azure esté disponible, este código va ahí sin cambios.

---

Estamos listos. Comparte los JSON de `02_sage.json`, `03_atlas.json` y `00_orchestrator.json` y arrancamos el Paso 1.
