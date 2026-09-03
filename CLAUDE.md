# CLAUDE.md — Claude Code en este proyecto

`AGENTS.md` tiene las reglas para todo agente. Este archivo agrega solo lo
específico de Claude Code — no repite `AGENTS.md`.

## Rol en este proyecto

No hay un segundo agente revisor (no hay equivalente a un "Codex" en Pangi).
El patrón real de trabajo es:

- **Claude Code** implementa: aplica patches, corre pruebas locales,
  ejecuta gitleaks/hooks, manipula archivos del repo directamente.
- **Contacto técnico backend de Pangi** provee acceso y credenciales reales
  cuando se necesitan (service keys, confirmación de contratos de API) —
  no revisa código, solo es fuente de verdad sobre el backend de Pangi.
  Se comunica solo vía WhatsApp, a través de Erick (nunca directo).
- **Erick** revisa y decide — ninguna decisión de producto, ningún patch
  sobre `workflows/*.json`, y ninguna llamada real contra la API de Pangi
  se ejecuta sin su aprobación explícita.
- **Claude (chat web)** dirige el diseño, verifica contra Swagger/DB real,
  y actúa como segunda revisión antes de que Claude Code aplique cambios —
  ese es el rol más cercano a "revisor cruzado" que existe aquí, pero no
  es simétrico: Claude Code ejecuta, Claude web/chat diseña y audita.

No asumas un revisor de código tipo pull-request — no existe en este flujo.

## Antes de proponer nada sobre fases numeradas

Lee `.ai/state.yaml` primero. No asumas correspondencia entre un número de
fase mencionado en el chat y un nombre de archivo — verifícalo ahí.

## No hacer aquí

- Nunca `git push`, abrir PRs, ni hacer merge (ver `AGENTS.md`).
- Nunca conectarte por SSH ni modificar el VPS, bases de datos de producción,
  n8n, o webhooks activos. Produce un runbook manual paso a paso para Erick
  en su lugar.
- Nunca pidas ni manejes tokens, credenciales o secretos de producción.
- Si necesitas contexto del entorno local o del VPS, pide que se corra
  `scripts/context-snapshot.sh` y se adjunte la salida — no asumas el estado
  de la infraestructura.
