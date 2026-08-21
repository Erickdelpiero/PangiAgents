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
- **Observabilidad:** Langfuse Cloud, plan gratuito — **temporal**
- **Canal actual:** Telegram (interfaz de desarrollo)

> **Langfuse Cloud tiene condición de salida.** Las trazas incluyen
> contexto clínico (procedimiento, condiciones, medicamentos, edad,
> sexo). El PHI Strip remueve identificadores directos antes de cada
> llamada al LLM, así que bajo Safe Harbor no hay PHI — pero no se
> habilita a pacientes reales sin autohospedar Langfuse dentro del
> Azure de Pangi. Ver `docs/roadmap-integracion-pangi.md`, riesgo R8.

> El canal es intercambiable por diseño. Los agentes son
> channel-agnostic; el acoplamiento vive solo en los bordes del
> orquestador (ingress y egress). El destino de producción es un widget
> embebido en pangi.com.

## Integración con Pangi

El catálogo —especialidades, procedimientos y ciudades— es propiedad de
Pangi y se administra desde `admin.pangi.com`. Este sistema **no
mantiene listas propias**: las sincroniza.

```
admin.pangi.com  →  API pública de Pangi  →  06_pangi_catalog_sync
                                                      ↓
                                              PostgreSQL local
                                                      ↓
                                              SAGE · NOVA · ATLAS
```

Los agentes leen el catálogo **desde PostgreSQL**, nunca llaman a la API
de Pangi durante la conversación. Dos razones: cero latencia HTTP
mientras el paciente espera, y si Pangi cae los agentes siguen operando
con el último catálogo conocido.

La sincronización corre cada hora. Cuando el stack esté en Azure con URL
estable, se le suma un Webhook Trigger para frescura casi instantánea y
el schedule baja a diario como reconciliación anti-deriva.

**Cinco endpoints de Pangi son públicos** (sin autenticación):
`speciality`, `countries`, `available-locations`, `doctors`, `date-slots`.
Eso permite construir catálogos y todo el flujo de NOVA hasta el momento
de reservar sin credencial de servicio.

Contratos verificados, riesgos abiertos y fases en
`docs/roadmap-integracion-pangi.md`.

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
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/007_fix_catalog_view.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/008_kb_i18n_names.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/009_kb_display_order.sql
psql -U pangi_user -h localhost -d pangi_dev -f db/migrations/010_pangi_doctors.sql
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
`007` corrige `v_pangi_catalog`: el LEFT JOIN duplicaba filas donde la KB
distingue más fino que Pangi (brackets vs. alineadores, corona vs. puente).
`008` traslada a la KB los nombres visibles en los tres idiomas, que hasta
entonces vivían solo dentro del literal `PROCEDURES` del motor de SAGE.
`009` traslada a la KB el orden de presentación de los procedimientos. El
motor numera la lista por índice y acepta ese número como respuesta, así
que el orden del array es lo que el paciente ve como "1.", "2.", "3." —
y el del literal es curado, no alfabético.
`010` extiende el espejo con doctores, clínicas y los procedimientos que
ofrece cada uno. El `_id` de clínica es lo que viaja como `clinic_address`
al consultar horarios y al reservar.

> **Los strings de Pangi se copian literalmente, nunca se escriben a
> mano.** Varios llevan guion largo (`–`, U+2013) y uno lleva espacio
> final (`Teeth Cleaning (Prophylaxis) `). Pangi identifica los
> tratamientos por string exacto, no por ObjectId.

## Workflows

Importar en n8n en este orden (los sub-workflows deben existir antes
que quienes los invocan):

1. `05_db_manager.json`
2. `04_handoff_manager.json`
3. `01_nova.json`, `02_sage.json`, `03_atlas.json`
4. `00_orchestrator_telegram.json`

Dos workflows son independientes — no los invoca nadie y no invocan a
nadie, así que se pueden importar en cualquier momento:

- **`06_pangi_catalog_sync.json`** — schedule horario. Trae el catálogo
  de Pangi (especialidades, procedimientos, ciudades) a las tablas
  espejo. Tiene guarda de plausibilidad: si llegan menos de 15
  especialidades no escribe nada, para que una respuesta vacía durante
  un despliegue de Pangi no borre el catálogo local. Cada corrida queda
  en `pangi_catalog_sync_log`.
- **`07_maintenance.json`** — schedule diario 04:00 más trigger manual.
  Purga `message_dedup` (>1 h) y marca sesiones vencidas como
  `expired`. **No borra sesiones ni historial**: la retención de datos
  es una decisión de política HIPAA, pendiente.

Va separado del de catálogo a propósito: son ciclos de vida distintos
—uno corre porque Pangi cambia, el otro porque pasa el tiempo— y ahí
vivirán las políticas de retención cuando se definan.

NOVA y SAGE consultan el catálogo antes del motor, vía `05_db_manager`
(`getCities`, `getProcedures`). Si esa llamada falla, los motores caen a
sus listas literales y la conversación continúa — degradación elegante,
no error.

Tras importar hay que reconectar credenciales manualmente — los exports
de n8n no las incluyen.

> **Al modificar un workflow en n8n, exportarlo y commitearlo.** Ya
> ocurrió una divergencia en la que n8n corría la versión parcheada y
> el repositorio guardaba la anterior. La fuente de verdad de lo que
> está corriendo es n8n; la del proyecto es este repositorio, y deben
> coincidir.

> **Al actualizar un sub-workflow, verificar que n8n quedó con la
> versión nueva.** Un `05_db_manager` desactualizado no da error: la
> operación desconocida devuelve `success: false` y el llamador cae a
> su fallback en silencio.

`workflows/_legacy/` contiene el orquestador original de WhatsApp vía
Evolution API, previo a la migración a Telegram. Se conserva como
referencia histórica; **no está en uso**. Evolution API quedó descartada:
las notificaciones de producción irán por la Cloud API oficial de Meta.

## Estado

MVP v2 funcional y demostrado. Integración con Pangi en curso: catálogo
sincronizado y mapeo completo (22/22 procedimientos, 36 ciudades).
Pendiente: cablear los agentes al catálogo, escritura de solicitudes vía
API, widget embebido y migración a Azure.

Tags de referencia: `mvp-v2-pre-pangi` (base estable previa a la
integración), `f1-catalog-sync` (sincronización de catálogo operativa).
