# AGENTS.md — reglas para agentes de codificación en este proyecto

Lee `.ai/project.md` y este archivo al empezar cualquier tarea. Lee
`.ai/decisions.md` antes de tocar dominio, API, seguridad o migraciones.
Lee `.ai/state.yaml` antes de referenciar cualquier documento por número de
fase — es la única fuente de verdad de qué archivo corresponde a qué etapa.

## Autoridad

**Puedes, sin pedir permiso:**

- leer el repositorio y la documentación;
- crear/modificar código de aplicación y tests; correr tests, linters, análisis estático;
- crear commits **locales**;
- proponer cambios y documentar decisiones en `.ai/decisions.md`;
- revisar el trabajo de otro agente.

**Requiere aprobación explícita de Erick:**

- `git push` y merge — un humano siempre hace push; ningún agente hace push de código;
- cualquier cosa que toque producción: VPS, base de datos de producción, n8n,
  webhooks activos, infraestructura viva;
- operaciones destructivas (`DROP`, borrado de datos) y migraciones potencialmente destructivas;
- cambios de secretos/credenciales;
- cambios arquitectónicos frente a lo cerrado en `.ai/decisions.md`.

Si una implementación entraría en conflicto con una decisión ya cerrada, no
inventes una regla nueva en silencio — señala el conflicto y pregunta.

## Reglas duras (genéricas — completar con las específicas del proyecto en `.ai/project.md`)

- **Nada sensible en Git:** secretos, `.env`, dumps de base de datos, datos
  reales de usuarios/pacientes/clientes, tokens, IDs privados. Tests usan
  datos sintéticos.
- El hook de pre-commit (`.githooks/pre-commit`) es obligatorio, no opcional.
  Si bloquea un commit legítimo, se ajusta la regla del hook — nunca se hace
  `git commit --no-verify` como solución.
- Cualquier operación sobre producción se documenta como runbook manual para
  que Erick lo ejecute — ningún agente ejecuta directamente contra producción
  salvo que `.ai/project.md` indique explícitamente lo contrario.

## Desarrollo y testing

(Completar por proyecto en `.ai/project.md`: layout de carpetas, cómo correr
tests, contra qué base de datos, convención de ramas.)
