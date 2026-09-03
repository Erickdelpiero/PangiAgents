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

### [2026-09-03] Purga de historial de git — reemplaza decisión anterior

**Contexto:** la entrada del 2026-09-01 ("Secreto histórico aceptado como
riesgo residual") aceptó no reescribir el historial de un API key
revocada. Al preparar `agent-harness`, la misma auditoría de higiene de
repo detectó nombres de colaboradores reales (contacto técnico backend,
encargado de infraestructura Azure, CEO de Pangi) expuestos en
`docs/roadmap-integracion-pangi.md` y en metadatos de commits/tags — no
solo en el working tree, sino en 25 commits de historial, en un repo
público.

**Decisión:** purgar el historial completo con `git filter-repo`
(`--replace-text` + `--replace-message`, ya que los mensajes de commit y
de un tag anotado también contenían nombres) y force-push de todas las
ramas y tags. Se aprovechó la misma operación para purgar también la API
key de Evolution API de la decisión anterior, ya que reescribir el
historial una sola vez es más limpio que hacerlo dos veces.

**Alternativas consideradas:** mantener la decisión original (aceptar
riesgo residual) — descartada porque el caso ya no es equivalente al de
la API key. Una credencial revocada (verificada con 401 contra el
servidor real) es un riesgo neutralizado en la práctica; la identidad de
personas activas hoy, en un repo público, no lo es — no hay un
equivalente a "probar que ya no sirve" para un nombre propio.

**Verificación:** `gitleaks detect` sobre los 25 commits (`no leaks
found`) y `grep` de los 3 nombres + la key vieja sobre `git log --all -p`
más mensajes de commits/tags — limpio, confirmado dos veces: primero
sobre el mirror purgado local, y de nuevo sobre un clon fresco desde
GitHub tras el push (para no depender de una copia local que pudiera
estar desincronizada del remoto real).

**Nota de exposición residual:** forks o clones de terceros hechos antes
del push, y la caché interna de GitHub de los SHA viejos, pueden
conservar el contenido purgado hasta que GitHub los recolecte — riesgo
bajo pero no cero, mismo criterio que ya se aplicó a la key.

**Estado:** cerrada. Reemplaza la entrada [2026-09-01] "Secreto histórico
aceptado como riesgo residual", que queda superseded.

### [2026-09-03] Diseño de F3-E cerrado — implementación diferida a la key

**Contexto:** diseño completo de la reserva real vía
POST /api/service/add-appointment revisado. De los 12 gaps identificados
inicialmente, 6 se resolvieron por relectura del contrato ya confirmado
(category, time_zone, phone, practice_id no son required — el backend
documenta comportamiento de fallback sin ellos; el nombre del campo de
referencia en la respuesta 200 es data._id, ya visible en el ejemplo del
Swagger capturado antes; el enum de payment_type ya estaba confirmado
dos veces). Quedaron 4 decisiones reales, resueltas así:

**Decisión:**
1. sched_test_patient_id se llena como literal en el nodo de preparación
   del payload (ID de prueba ya documentado en .ai/project.md, no es PHI
   ni secreto — dentro de las reglas del proyecto).
2. is_for_patient y family_member se OMITEN del payload (no se hardcodea
   true) — el backend define su propio default para estos campos
   opcionales.
3. En caso de 422 ("slot already booked"), NOVA vuelve a sched_slots con
   la lista de horarios RE-CONSULTADA (no la lista vieja cacheada), para
   no repetir el mismo conflicto con datos obsoletos.
4. La implementación completa (nodo prep, nodo HTTP, wiring, manejo de
   errores) queda diferida hasta que llegue X-Pangi-Service-Key — se
   implementa y prueba todo en un solo bloque, sin un modo mock/live
   intermedio que agregue superficie de confusión entre ambientes.

**Alternativas consideradas:** mergear F3-E ahora detrás de un flag de
modo mock, activable a live cuando llegue la key — descartado por
complejidad añadida sin necesidad real, dado que la key se espera pronto.

**Estado:** cerrada. Diseño listo para implementación inmediata apenas
se resuelva el bloqueante externo (X-Pangi-Service-Key).

### [2026-09-03] X-Pangi-Service-Key recibida, F3-E implementada pendiente de prueba real

**Contexto:** el contacto técnico backend de Pangi reenvió
X-Pangi-Service-Key (credencial "Pangi Service Key", HTTP Header Auth, ya
cargada en n8n). Se verificó con curl → 200 contra producción. Con el
bloqueante externo resuelto, se procedió con la implementación completa
que había quedado diferida en la entrada anterior: nodo de preparación
del payload (`📦 ¿Reservar Cita?`), nodo HTTP (`🌐 API — Reservar Cita`),
wiring, y manejo de las 3 ramas de respuesta (200/422/genérico) en el
motor.

**Decisión:**
1. La implementación se hizo completa en `workflows/01_nova.json`, tal
   como diseñado — sin llamar la API real: los 5 escenarios de respuesta
   HTTP (200 con `data._id`, 422 con horarios frescos, 422 sin horarios
   frescos, 401, timeout/sin respuesta) se probaron con mocks del nodo
   HTTP, más una batería de equivalencia sobre 18 escenarios que no
   tocan booking. Queda pendiente de revisión de diff (Erick/Claude-web)
   y de una primera prueba real contra Telegram antes de cerrar la fase.
2. **Hallazgo de diseño corregido:** el diseño original pedía validar en
   `📦 ¿Reservar Cita?` la presencia de `nova.sched_test_patient_id`
   antes de armar el payload. Ese campo nunca se puebla en el estado de
   sesión — la Opción A (paciente de prueba) lo fija como literal
   directamente en el nodo, no lo lee de `nova`. Validarlo tal cual
   habría hecho que `needBooking` fuera `false` siempre, bloqueando toda
   reserva de forma permanente. Se quitó ese campo de la lista de
   validación; el resto de la validación (fecha/hora/doctor/clínica
   seleccionados) y el literal `TEST_PATIENT_ID` quedan sin cambios.

**Estado:** in_review. Pendiente de aprobación del diff por Erick y de
la primera prueba real en Telegram.

### [2026-09-03] F3-E cerrada — primera reserva real exitosa

**Contexto:** con X-Pangi-Service-Key verificada y la implementación de
F3-E aprobada, se hizo la primera prueba real en Telegram: agendamiento
completo con Kevin Fleishman (Fort Lauderdale) y paciente de prueba
lola_pruebas. La reserva se creó correctamente en Pangi (appointment_ref
real de Mongo, ej. 6a99a6a8a1c2d2c7e2998f13, confirmada visible en
admin.pangi.com).

**Hallazgo durante la prueba:** discrepancia de horario entre lo
seleccionado en el chat (09:00) y lo mostrado en el admin panel de
Pangi (04:00 AM). Investigado con logs de n8n + curl directo contra
producción (sin pasar por nuestro sistema): confirmado que
date-slots-range devuelve time_zone=America/Bogota para la clínica de
Fort Lauderdale del doctor de prueba — dato de configuración incorrecto
del lado de Pangi, no un bug de nuestro código (que lee y persiste el
dato tal cual lo recibe, sin transformarlo). Reportado al contacto
técnico backend de Pangi.

**Decisión:** cerrar F3-E — el flujo de reserva real funciona
correctamente end-to-end de nuestro lado. El hallazgo de timezone queda
como item externo, sin bloquear el cierre.

**Estado:** cerrada.

### [2026-09-03] Requerimiento capturado — botones interactivos en Telegram (patrón portable a la web)

**Contexto:** el CEO de Pangi pidió — solicitado por el CEO de Pangi,
fecha exacta no registrada, es una petición previa a esta fecha —
agregar botones interactivos en Telegram para reducir las casuísticas de
texto libre que hoy debe manejar el motor conversacional (typos,
respuestas ambiguas, valores fuera de enum). La intención es explícita y
no cosmética: los mismos patrones de UI/UX deben reutilizarse en la
migración a la web de Pangi (widget / F6), de modo que el diseño de
interacción se piense una sola vez y se porte.

**Decisión:** registrar el requerimiento y diferir su diseño e
implementación. A la fecha NO hay diseño de interacción, ni mapeo de qué
estados del motor pasarían de texto libre a botones, ni implementación en
`workflows/*.json`. Queda como fase `parked` en `.ai/state.yaml`
(`id: UX-BTN`) para que no se pierda de vista; se retoma cuando sea
prioridad, idealmente coordinado con F6 (widget) para diseñar el patrón
una sola vez.

**Alternativas consideradas:**
- Abrirlo como fase activa ahora — descartado: no es prioridad frente a
  F6 y al cierre de la integración con la API de Pangi; diseñarlo antes
  del widget arriesga rehacer el trabajo de UX dos veces.
- Registrarlo solo en `docs/roadmap-integracion-pangi.md` — descartado:
  ese doc está desactualizado respecto a `.ai/state.yaml` y su alcance es
  la integración con la API de Pangi; este requerimiento es transversal
  (canal Telegram hoy + web después).

**Estado:** cerrada como registro del requerimiento. El trabajo en sí
queda `parked` en `.ai/state.yaml`.