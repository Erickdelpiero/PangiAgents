# widget/ — Chat widget web de Pangi (F6)

Front standalone del canal web. Habla con `workflows/00_orchestrator_web.json`
(webhook n8n), que reusa el mismo pipeline que `00_orchestrator_telegram.json`
(dedup → sesión → router NLU → NOVA/SAGE/ATLAS).

> ⚠️ **Fase 1 usa una identidad de prueba fija compartida (`TEST_WEB_PHONE`).**
> Eso significa **una sola conversación activa a la vez en todo el sistema**:
> todos los visitantes del widget resuelven al mismo `users.id` y, por el índice
> `idx_one_active_session_per_user`, comparten la misma sesión. **No probar desde
> dos pestañas / navegadores / personas en simultáneo** — se pisan el estado de
> conversación entre sí. Queda así hasta que exista identidad real por paciente
> (F3E-ID, `parked`).

## Por qué esta carpeta

No había precedente de assets de front en el árbol (`db/`, `docs/`, `prompts/`,
`scripts/`, `workflows/`). `widget/` a nivel raíz sigue el mismo patrón que
`workflows/` y `scripts/`: un concern de primer nivel. El roadmap ya define el
widget como "standalone vía script tag", así que es un `.js` suelto, no un
proyecto con build.

## Archivos

| Archivo | Qué es |
|---|---|
| `pangi-widget.js` | El widget. IIFE, sin dependencias, Shadow DOM. Se inyecta con `<script src="…/pangi-widget.js" data-endpoint="…/webhook/pangi-widget" defer></script>`. |
| `demo.html` | Página de prueba local. **No se despliega.** |

## Estado (F6 Fase 1)

- ✅ launcher + panel + lista de mensajes + composer de texto
- ✅ render de `buttons` si la respuesta los trae (contrato ya definido; hoy
  ningún motor los emite — `UX-BTN` parked). El click va como `button_reply`.
- ✅ `conversationId` estable en `localStorage` (mantiene la sesión del backend)
- ⛔ sin JWT / auth real (F6.4 diferido — el front de pangi.com será
  reemplazado por WordPress, mecanismo de auth incierto). La identidad de
  prueba vive en el backend, no aquí:
  `00_orchestrator_web` → extractor → `TEST_WEB_PHONE` / `TEST_WEB_PANGI_USER_ID`.
  **Es compartida → una sola conversación simultánea en todo el sistema** (ver
  la advertencia al inicio de este README).
- ⛔ sin adjuntos (F6.3 — iteración aparte)

## Pendiente de confirmación externa

- **Dominio CORS**: hoy es el placeholder `https://REEMPLAZAR-dominio-widget.example` en
  `00_orchestrator_web.json` (`allowedOrigins` del Webhook + header de
  `📤 Respuesta al Widget`). Actualizar al dominio real (staging del tercero +
  prod) cuando el CEO lo confirme.
- **Empaquetado**: script-tag propio vs. componente que integra el tercero de
  WordPress. No cambia el backend.
