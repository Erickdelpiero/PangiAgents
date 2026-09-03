# workflow.md — protocolo de colaboración entre agentes

## Principio

El agente que implementa no es automáticamente quien valida su propio
trabajo. Más allá de eso, no hay una asignación de roles fija — se ajusta
según la tarea:

```
propone/implementa  →  revisa
Claude Code          →  Codex
Codex                →  Claude Code
Claude Web            →  GPT Web  (fase de diseño, antes de escribir código)
```

## Fase de diseño (antes de código)

1. Se propone una arquitectura o decisión con un formato corto y estructurado
   (no prosa larga — ver comunicación abajo).
2. Si la propuesta depende de estado real del entorno (VPS, local, servicios
   externos), se adjunta la salida de `scripts/context-snapshot.sh`. Esto no
   es opcional cuando la propuesta hace afirmaciones sobre infraestructura
   existente — el piloto demostró que omitirlo cambia el feedback recibido.
3. El otro agente revisa contra la evidencia adjunta, no contra suposiciones.
4. Al cerrar, se registra en `.ai/decisions.md` con el formato definido ahí.
5. Si la fase produce varios documentos numerados, `.ai/state.yaml` se
   actualiza en el mismo momento que se cierra cada uno — nunca después.

## Fase de implementación

1. Un agente (Claude Code / Codex) implementa contra lo cerrado en
   `.ai/decisions.md` y las reglas de `AGENTS.md`.
2. El otro agente revisa el diff — no solo la intención, el código real.
3. Cualquier bug encontrado se corrige y se agrega un test que lo cubra.
4. Ninguna operación sobre producción ocurre en esta fase sin aprobación
   explícita — el agente entrega un runbook manual.

## Comunicación (aplica a Claude Web / GPT Web / Claude Code)

- Respuestas breves por defecto. Detalle extenso solo si se pide
  explícitamente.
- En fase de diseño con documentos largos: preferir revisión "uno propone,
  otro da feedback" en vez de que ambos generen propuestas independientes
  completas — el costo de tiempo de leer dos propuestas largas no se
  justificó en la práctica salvo para la arquitectura inicial de más alto
  nivel.
