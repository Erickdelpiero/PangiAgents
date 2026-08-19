# Pangi — Sistema de Asistentes Inteligentes

Sistema multi-agente conversacional para la plataforma de turismo médico
**Pangi**. Guía al paciente en cotización de procedimientos, comparación
de destinos y agendamiento de citas — en español, inglés y portugués.

## Agentes

| Agente | Rol |
|---|---|
| **NOVA** | Orientación inicial y agendamiento de citas |
| **SAGE** | Intake clínico para solicitudes de cotización |
| **ATLAS** | Comparación de destinos y costo total real de viaje |

Orquestados por `00_orchestrator_telegram`, que resuelve consentimiento,
detección de idioma, ruteo por intención y handoffs entre agentes sin
pérdida de contexto.

## Stack

- **Orquestación:** n8n v1.121.3 (self-hosted, npm)
- **LLM:** Claude Haiku (NLU) + Sonnet (NLG) vía proxy LiteLLM
- **Estado:** PostgreSQL 16 (`pangi_dev`)
- **Observabilidad:** Langfuse (self-hosted)
- **Canal actual:** Telegram (interfaz de desarrollo)

> El canal es intercambiable por diseño. Los agentes son
> channel-agnostic; el acoplamiento vive solo en los bordes del
> orquestador (ingress y egress). El destino de producción es un widget
> embebido en pangi.com.

## Estructura

```
db/migrations/   Migraciones SQL en orden de aplicación
db/snapshots/    Dumps de referencia de la DB viva
workflows/       Exports de n8n (importables sin edición manual)
prompts/         Prompts de sistema por agente y estado
docs/            Roadmap y notas de migración
```

## Setup de base de datos

Aplicar en orden:

```bash
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/001_initial_schema.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/002_kb_paired_format.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/003_dedup_and_session_index.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/004_pangi_integration.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/005_plastic_surgery_mapping.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/006_pangi_catalog_tables.sql
```

`001` crea el schema y siembra la knowledge base (22 procedimientos:
12 dental + 10 cirugía plástica) y 10 destinos de ATLAS.
`002` migra `critical_questions` al formato `{key, question}`.
`003` documenta objetos creados en caliente durante el MVP.
`004` mapea la taxonomía de la KB contra el catálogo de Pangi (dental 12/12)
y agrega las columnas de identidad para el widget.
`005` completa el mapeo de cirugía plástica (10/10) tras cargar los
procedimientos estéticos en el Admin. Los 22 procedimientos resuelven.
`006` crea el espejo local del catálogo de Pangi que alimenta el workflow
`06_pangi_catalog_sync`.

## Workflows

Importar en n8n en este orden (los sub-workflows deben existir antes
que quienes los invocan):

1. `05_db_manager.json`
2. `04_handoff_manager.json`
3. `01_nova.json`, `02_sage.json`, `03_atlas.json`
4. `00_orchestrator_telegram.json`

Tras importar hay que reconectar credenciales manualmente — los exports
de n8n no las incluyen.

`workflows/_legacy/` contiene el orquestador original de WhatsApp vía
Evolution API, previo a la migración a Telegram. Se conserva como
referencia histórica; **no está en uso**.

## Estado

MVP v2 funcional y demostrado. Próxima fase: integración con la
plataforma Pangi (Angular + NestJS + MongoDB sobre Azure) — widget
embebido, catálogos dinámicos desde el admin, y creación real de
solicitudes de tratamiento vía API.
