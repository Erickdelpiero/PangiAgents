# project.md — contexto fijo del proyecto

## Qué es

Sistema de tres agentes conversacionales (NOVA, SAGE, ATLAS) para Pangi,
plataforma de turismo médico. NOVA orienta y agenda citas, SAGE hace intake
clínico para cotizaciones, ATLAS compara destino/costo. Para el CEO de
Pangi, contratante de Erick.

## Stack

- Lenguaje/framework: N8N v1.121.3 (self-hosted, npm) — orquestación por
  workflows JSON con nodos Code (JS)
- Base de datos: PostgreSQL 16 (`pangi_dev`)
- Infraestructura: VPS Contabo (`vmi2857037`, alias SSH `VPS-Contabo`,
  IP 157.173.96.16) — hoy. Azure (tenant de Pangi) — destino de producción,
  lo provisiona el encargado de infraestructura Azure del lado Pangi
- Otros servicios externos: LiteLLM (proxy a Claude Haiku/Sonnet), Langfuse
  (observabilidad), Telegram (canal de pruebas activo), API de Pangi
  (`pangi.com/api`, NestJS + MongoDB, documentada en `/api/docs-json`)

## Entornos

| Entorno | Dónde vive | Cómo se accede |
|---|---|---|
| Local | `~/Documents/Projects/pangi-dev` (Ubuntu 24.04) | terminal directo |
| Dev/pruebas | VPS Contabo, n8n propio | `ssh VPS-Contabo`, editor n8n vía subdominio |
| Producción (futuro) | Azure, tenant Pangi | pendiente — lo provisiona el encargado de infraestructura Azure del lado Pangi |

## Visibilidad del repo

- [x] Público — `github.com/Erickdelpiero/PangiAgents`. Auditado 2026-09-01
      (ver decisions.md); un secreto histórico de severidad efectiva baja
      aceptado como riesgo residual, sin reescribir historial.

## Decisor humano

Erick — cualquier cosa que toque producción, secretos, o el body de una
llamada real a la API de Pangi requiere su aprobación explícita.

## Reglas duras específicas de este proyecto

- NUNCA PHI (nombres, teléfonos, condiciones médicas reales de pacientes)
  en Git, logs, ni workflows exportados. Solo IDs de prueba documentados
  (ej. `lola_pruebas` = `69fe989e637c149cdcb2075f`).
- NUNCA credenciales de servicio (service keys, API keys) como parámetro de
  nodo n8n exportado — solo como credencial n8n (UI encriptada) o `.env`
  excluido por `.gitignore`.
- Antes de cada commit: `gitleaks protect --staged` (hook activo).
- Ningún patch sobre `workflows/*.json` se genera sin `md5sum` de la base
  confirmado primero, y sin aprobación explícita del diseño.
- Toda afirmación sobre el comportamiento de la API de Pangi se verifica
  contra Swagger (`pangi.com/api/docs-json`) o la DB real — nunca se asume
  por memoria de conversaciones anteriores con el contacto técnico backend
  de Pangi.
- Cualquier nombre real de una persona nueva que aparezca en la
  conversación de trabajo (fuera del equipo de agentes NOVA/SAGE/ATLAS) se
  agrega INMEDIATAMENTE a `.ai/anonymize-list.txt`, sección `[REDACT]`, sin
  esperar a que Erick lo pida. El pre-commit hook lo hace cumplir
  automáticamente — no depender de revisión manual.

## Contrapartes externas

- Contacto técnico backend de Pangi (India, WhatsApp) — construye endpoints
  a pedido; verificar siempre contra Swagger/DB real, no asumir su palabra.
- CEO de Pangi — decisiones de producto, mensajes breves en español.
- Encargado de infraestructura Azure (lado Pangi).