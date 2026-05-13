# /prompts — Fuente de Verdad de Prompts de Claude

**Proyecto:** Sistema NOVA · SAGE · ATLAS — Pangi  
**Mantenido por:** Erick Del Piero Gonzales  
**Última actualización:** Mayo 2026

---

## Propósito

Este directorio contiene la documentación completa de todos los prompts que se envían  
a la API de Claude en el sistema NOVA · SAGE · ATLAS.

**Regla de oro:** cualquier cambio de comportamiento de un agente empieza editando el `.md`  
correspondiente aquí. Solo después se actualiza el nodo N8N (o el archivo Python en LangGraph).

---

## Archivos

| Archivo | Agente | Estado(s) | Modelo |
|---------|--------|-----------|--------|
| `sage_system_base.md` | SAGE | todos | — |
| `sage_questioning.md` | SAGE | `questioning` | Sonnet |
| `sage_handoff_received.md` | SAGE | `handoff_received`, `selecting_specialty` | Sonnet |
| `sage_procedure_confirmed.md` | SAGE | `procedure_confirmed` (solo EN/PT) | Sonnet |
| `sage_summary.md` | SAGE | `summary` | Sonnet |
| `atlas_nlg.md` | ATLAS | `comparison_done`, `exploring`, `has_quotes_check`, `checklist_shown` | Sonnet |
| `nova_nlg.md` | NOVA | `handoff_sage`, `handoff_atlas`, `ask_city`, `fallback` | Haiku |

---

## Convención de versiones

`MAYOR.MENOR.PATCH`  
- PATCH: corrección de tono, ortografía, ejemplos  
- MENOR: cambio de instrucción o nuevo caso edge  
- MAYOR: rediseño de la estructura del prompt o cambio de modelo

---

## Relación con N8N

Los prompts en N8N están inline en los nodos `📦 Preparar — NLG [AGENTE]`.  
Este directorio es la fuente de verdad — N8N los tiene como copia operativa.

### Flujo de cambio de prompt
```
1. Editar .md en /prompts (PR / revisión de equipo)
2. Copiar el system prompt actualizado al nodo N8N correspondiente
3. Testear en WhatsApp
4. Confirmar y hacer commit del .md
```

---

## PHI y seguridad

Todos los prompts están diseñados para funcionar sin datos personales del paciente.  
El nodo `🔐 Strip PHI` en cada agente garantiza que Claude recibe solo datos clínicos.  
Ver `sage_system_base.md` para la política PHI completa.

---

## Roadmap de prompts

**Fase actual (MVP):** prompts inline en N8N, `.md` como documentación  
**Post-MVP (LangGraph):** archivos `.md` se convierten en system prompts que Python lee directamente  
**Azure:** prompts almacenados en tabla PostgreSQL `prompts` con versionado y hot-swap
