# decisions.md — bitácora de decisiones cerradas

## Formato de cada entrada

### [YYYY-MM-DD] Título corto de la decisión

**Contexto:** por qué surgió esta decisión.
**Decisión:** qué se decidió, en una o dos frases.
**Alternativas consideradas:** qué otras opciones se evaluaron y por qué no.
**Estado:** cerrada | reemplazada por [fecha/entrada]

---

### [2026-09-01] Adopción de agent-harness v0.1

**Contexto:** framework validado en proyecto piloto previo
(monthly-financial-ledger); se decide adoptarlo en un proyecto real
(pangi-dev) para evitar reexplicar contexto en cada sesión nueva y no
perder estado entre agentes (Claude web, Claude Code, el contacto técnico
backend de Pangi vía WhatsApp).
**Decisión:** instalar agent-harness sobre pangi-dev tras auditoría de
seguridad limpia.
**Alternativas consideradas:** seguir sin framework, dependiendo solo de
memoria de conversación — descartado por riesgo de repetir bugs de
sincronización de roadmap ya vistos en el piloto.
**Estado:** cerrada

### [2026-09-01] Secreto histórico aceptado como riesgo residual

**Contexto:** auditoría previa a instalar el framework encontró una API key
real de Evolution API en `workflows/_legacy/00_orchestrator.json`
(commit `0966fdd7`), en repo público.
**Decisión:** se acepta el riesgo sin reescribir el historial de git.
Verificado con una llamada real (`GET /instance/fetchInstances` con esa
key) que el servidor responde `401` — la key está revocada y la instancia
que protegía ya no existe.
**Alternativas consideradas:** purgar el historial con `git filter-repo` +
force-push — descartado por el costo/fricción frente a un riesgo ya
neutralizado en la práctica.
**Estado:** cerrada