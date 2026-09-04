/* ============================================================================
 * pangi-widget.js — Chat widget standalone para Pangi  (F6 · Fase 1)
 * ----------------------------------------------------------------------------
 * Sin dependencias. Se inyecta con:
 *
 *   <script src="https://<host>/pangi-widget.js"
 *           data-endpoint="https://<n8n>/webhook/pangi-widget"
 *           defer></script>
 *
 * Atributos del <script>:
 *   data-endpoint   (requerido) URL del Webhook de 00_orchestrator_web.
 *   data-title      (opcional)  título del panel. Default: "Pangi".
 *   data-autostart  (opcional)  "true" → al abrir manda un saludo para
 *                               disparar el aviso de privacidad. Default: no.
 *
 * ALCANCE FASE 1:
 *   - launcher + panel + lista de mensajes + composer de texto.
 *   - render de botones si la respuesta trae `buttons` (contrato ya definido;
 *     hoy NINGÚN motor los emite — UX-BTN parked). El click se manda como
 *     messageType 'button_reply'.
 *   - NO hay JWT / auth real (F6.4 diferido — reemplazo del front por WordPress).
 *     La identidad de prueba vive en el backend (00_orchestrator_web →
 *     extractor: TEST_WEB_PHONE / TEST_WEB_PANGI_USER_ID).
 *   - NO hay adjuntos (F6.3 — iteración aparte).
 * ==========================================================================*/
(function () {
  'use strict';

  if (window.__pangiWidgetLoaded) return;
  window.__pangiWidgetLoaded = true;

  // ── Config ────────────────────────────────────────────────────────────────
  var thisScript =
    document.currentScript ||
    (function () {
      var s = document.getElementsByTagName('script');
      return s[s.length - 1];
    })();

  var ENDPOINT = (thisScript && thisScript.getAttribute('data-endpoint')) || '';
  var TITLE = (thisScript && thisScript.getAttribute('data-title')) || 'Pangi';
  var AUTOSTART =
    (thisScript && thisScript.getAttribute('data-autostart')) === 'true';

  if (!ENDPOINT) {
    console.error('[pangi-widget] falta data-endpoint en el <script>. Widget no se monta.');
    return;
  }

  var TOKENS = {
    navy: '#1B1D4B',
    green: '#8AC43F',
    font: '"Open Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
  };

  // ── conversationId estable (para que la sesión del backend persista) ──────
  var LS_KEY = 'pangi_conv_id';
  var CONV_ID = null;
  try {
    CONV_ID = window.localStorage.getItem(LS_KEY);
  } catch (e) {
    /* modo privado / storage bloqueado */
  }
  if (!CONV_ID) {
    CONV_ID =
      (window.crypto && window.crypto.randomUUID && window.crypto.randomUUID()) ||
      'web-' + Date.now() + '-' + Math.random().toString(16).slice(2);
    try {
      window.localStorage.setItem(LS_KEY, CONV_ID);
    } catch (e) {
      /* noop */
    }
  }

  var uid = function () {
    return (
      (window.crypto && window.crypto.randomUUID && window.crypto.randomUUID()) ||
      'm-' + Date.now() + '-' + Math.random().toString(16).slice(2)
    );
  };

  // ── Estado ────────────────────────────────────────────────────────────────
  var state = {
    open: false,
    sending: false,
    messages: [] // { role:'user'|'bot'|'error', text, buttons?:[[{text,data}]] }
  };

  // ── Shadow DOM host ───────────────────────────────────────────────────────
  var host = document.createElement('div');
  host.id = 'pangi-widget-root';
  host.style.all = 'initial';
  var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;

  var style = document.createElement('style');
  style.textContent = [
    ':host, * { box-sizing: border-box; }',
    '.pw-wrap { position: fixed; right: 20px; bottom: 20px; z-index: 2147483000;',
    '  font-family: ' + TOKENS.font + '; }',

    /* Launcher */
    '.pw-launcher { width: 56px; height: 56px; border-radius: 50%; border: 0;',
    '  background: ' + TOKENS.navy + '; color: #fff; cursor: pointer;',
    '  box-shadow: 0 6px 20px rgba(0,0,0,.25); display: flex; align-items: center;',
    '  justify-content: center; transition: transform .15s ease; }',
    '.pw-launcher:hover { transform: scale(1.05); }',
    '.pw-launcher:focus-visible { outline: 3px solid ' + TOKENS.green + '; outline-offset: 2px; }',
    '.pw-launcher svg { width: 26px; height: 26px; fill: #fff; }',

    /* Panel */
    '.pw-panel { position: absolute; right: 0; bottom: 72px; width: 360px; height: 520px;',
    '  max-height: calc(100vh - 110px); background: #fff; border-radius: 14px;',
    '  box-shadow: 0 12px 40px rgba(0,0,0,.28); display: none; flex-direction: column;',
    '  overflow: hidden; }',
    '.pw-panel.pw-open { display: flex; }',

    '.pw-header { background: ' + TOKENS.navy + '; color: #fff; padding: 14px 16px;',
    '  display: flex; align-items: center; justify-content: space-between; flex: none; }',
    '.pw-header .pw-title { font-size: 15px; font-weight: 700; }',
    '.pw-close { background: transparent; border: 0; color: #fff; font-size: 20px;',
    '  line-height: 1; cursor: pointer; padding: 4px; border-radius: 6px; }',
    '.pw-close:focus-visible { outline: 2px solid ' + TOKENS.green + '; }',

    '.pw-messages { flex: 1 1 auto; overflow-y: auto; padding: 14px; background: #f4f5f8;',
    '  display: flex; flex-direction: column; gap: 8px; }',

    '.pw-msg { max-width: 82%; padding: 9px 12px; border-radius: 12px; font-size: 14px;',
    '  line-height: 1.4; white-space: pre-wrap; word-wrap: break-word; }',
    '.pw-msg.pw-bot { align-self: flex-start; background: #fff; color: #1a1a1a;',
    '  border: 1px solid #e3e5ea; border-bottom-left-radius: 4px; }',
    '.pw-msg.pw-user { align-self: flex-end; background: ' + TOKENS.green + '; color: #10240a;',
    '  border-bottom-right-radius: 4px; }',
    '.pw-msg.pw-error { align-self: flex-start; background: #fdecec; color: #8a1c1c;',
    '  border: 1px solid #f3c2c2; }',

    '.pw-typing { align-self: flex-start; display: inline-flex; gap: 4px; padding: 10px 12px;',
    '  background: #fff; border: 1px solid #e3e5ea; border-radius: 12px; }',
    '.pw-typing i { width: 6px; height: 6px; border-radius: 50%; background: #b3b8c2;',
    '  display: inline-block; animation: pw-bounce 1s infinite ease-in-out; }',
    '.pw-typing i:nth-child(2) { animation-delay: .15s; }',
    '.pw-typing i:nth-child(3) { animation-delay: .3s; }',
    '@keyframes pw-bounce { 0%,80%,100% { transform: translateY(0); opacity:.5; }',
    '  40% { transform: translateY(-4px); opacity:1; } }',

    '.pw-btns { display: flex; flex-wrap: wrap; gap: 6px; align-self: flex-start;',
    '  margin-top: 2px; }',
    '.pw-btns button { border: 1px solid ' + TOKENS.navy + '; background: #fff;',
    '  color: ' + TOKENS.navy + '; border-radius: 999px; padding: 6px 12px; font-size: 13px;',
    '  cursor: pointer; font-family: inherit; }',
    '.pw-btns button:hover { background: ' + TOKENS.navy + '; color: #fff; }',
    '.pw-btns button:disabled { opacity: .5; cursor: default; }',

    '.pw-composer { flex: none; display: flex; gap: 8px; padding: 10px; border-top: 1px solid #e3e5ea;',
    '  background: #fff; }',
    '.pw-composer textarea { flex: 1 1 auto; resize: none; border: 1px solid #cfd3db;',
    '  border-radius: 10px; padding: 8px 10px; font: inherit; font-size: 14px; max-height: 96px;',
    '  min-height: 38px; outline: none; }',
    '.pw-composer textarea:focus { border-color: ' + TOKENS.navy + '; }',
    '.pw-send { flex: none; border: 0; background: ' + TOKENS.navy + '; color: #fff;',
    '  border-radius: 10px; width: 42px; cursor: pointer; }',
    '.pw-send:disabled { opacity: .5; cursor: default; }',
    '.pw-send:focus-visible { outline: 2px solid ' + TOKENS.green + '; }',
    '.pw-send svg { width: 18px; height: 18px; fill: #fff; }',

    '.pw-hint { font-size: 12px; color: #6b7280; align-self: center; padding: 4px 0; }',

    '@media (max-width: 480px) {',
    '  .pw-wrap { right: 0; bottom: 0; }',
    '  .pw-panel { position: fixed; inset: 0; width: 100vw; height: 100vh; max-height: 100vh;',
    '    border-radius: 0; }',
    '  .pw-launcher { position: fixed; right: 16px; bottom: 16px; }',
    '}'
  ].join('\n');

  // ── Markup ────────────────────────────────────────────────────────────────
  var wrap = document.createElement('div');
  wrap.className = 'pw-wrap';
  wrap.innerHTML = [
    '<button class="pw-launcher" type="button" aria-haspopup="dialog" aria-expanded="false"',
    '        aria-label="Abrir chat de Pangi">',
    '  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 2H4a2 2 0 0 0-2 2v18l4-4h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2z"/></svg>',
    '</button>',
    '<section class="pw-panel" role="dialog" aria-modal="false" aria-label="Chat de Pangi">',
    '  <header class="pw-header">',
    '    <span class="pw-title"></span>',
    '    <button class="pw-close" type="button" aria-label="Cerrar chat">&times;</button>',
    '  </header>',
    '  <div class="pw-messages" role="log" aria-live="polite" aria-relevant="additions"></div>',
    '  <form class="pw-composer">',
    '    <textarea rows="1" placeholder="Escribe tu mensaje…" aria-label="Mensaje"></textarea>',
    '    <button class="pw-send" type="submit" aria-label="Enviar">',
    '      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 21l21-9L2 3v7l15 2-15 2z"/></svg>',
    '    </button>',
    '  </form>',
    '</section>'
  ].join('\n');

  root.appendChild(style);
  root.appendChild(wrap);

  var el = {
    launcher: wrap.querySelector('.pw-launcher'),
    panel: wrap.querySelector('.pw-panel'),
    title: wrap.querySelector('.pw-title'),
    close: wrap.querySelector('.pw-close'),
    messages: wrap.querySelector('.pw-messages'),
    form: wrap.querySelector('.pw-composer'),
    textarea: wrap.querySelector('textarea'),
    send: wrap.querySelector('.pw-send')
  };
  el.title.textContent = TITLE + ' · NOVA';

  // ── Render ────────────────────────────────────────────────────────────────
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function render() {
    el.messages.innerHTML = '';
    state.messages.forEach(function (m, idx) {
      var b = document.createElement('div');
      b.className =
        'pw-msg ' + (m.role === 'user' ? 'pw-user' : m.role === 'error' ? 'pw-error' : 'pw-bot');
      b.textContent = m.text;
      el.messages.appendChild(b);

      var isLast = idx === state.messages.length - 1;
      if (m.role === 'bot' && isLast && m.buttons && m.buttons.length) {
        var row = document.createElement('div');
        row.className = 'pw-btns';
        m.buttons.forEach(function (line) {
          line.forEach(function (btn) {
            var bt = document.createElement('button');
            bt.type = 'button';
            bt.textContent = btn.text;
            bt.disabled = state.sending;
            bt.addEventListener('click', function () {
              send(btn.data || btn.text, 'button_reply');
            });
            row.appendChild(bt);
          });
        });
        el.messages.appendChild(row);
      }
    });

    if (state.sending) {
      var t = document.createElement('div');
      t.className = 'pw-typing';
      t.setAttribute('aria-label', 'NOVA está escribiendo');
      t.innerHTML = '<i></i><i></i><i></i>';
      el.messages.appendChild(t);
    }

    if (!state.messages.length && !state.sending) {
      var hint = document.createElement('div');
      hint.className = 'pw-hint';
      hint.textContent = 'Escribe para comenzar la conversación.';
      el.messages.appendChild(hint);
    }

    el.messages.scrollTop = el.messages.scrollHeight;
    el.textarea.disabled = state.sending;
    el.send.disabled = state.sending;
  }

  // ── Normalizar `buttons` de la respuesta a filas [[{text,data}]] ─────────
  function normalizeButtons(raw) {
    if (!Array.isArray(raw) || !raw.length) return [];
    var rows = Array.isArray(raw[0]) ? raw : raw.map(function (b) { return [b]; });
    return rows
      .map(function (line) {
        return (line || [])
          .filter(function (b) { return b && (b.text || b.data); })
          .map(function (b) {
            return { text: String(b.text || b.data), data: String(b.data || b.text) };
          });
      })
      .filter(function (line) { return line.length; });
  }

  // ── Transporte ────────────────────────────────────────────────────────────
  function send(text, type) {
    text = (text == null ? '' : String(text)).trim();
    if (!text || state.sending) return;

    state.messages.push({ role: 'user', text: text });
    state.sending = true;
    render();

    fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        conversationId: CONV_ID,
        text: text,
        type: type === 'button_reply' ? 'button_reply' : 'text',
        clientMsgId: uid()
      })
    })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        state.sending = false;
        var reply = (data && (data.text || data.responseText)) || '(sin respuesta)';
        state.messages.push({
          role: 'bot',
          text: reply,
          buttons: normalizeButtons(data && data.buttons)
        });
        render();
      })
      .catch(function (err) {
        state.sending = false;
        state.messages.push({
          role: 'error',
          text: 'No pude conectar. Toca para reintentar.'
        });
        render();
        // el último bubble de error reintenta el mismo mensaje
        var errs = el.messages.querySelectorAll('.pw-msg.pw-error');
        var lastErr = errs[errs.length - 1];
        if (lastErr) {
          lastErr.style.cursor = 'pointer';
          lastErr.addEventListener(
            'click',
            function () {
              // quitar el bubble de error y reenviar
              for (var i = state.messages.length - 1; i >= 0; i--) {
                if (state.messages[i].role === 'error') {
                  state.messages.splice(i, 1);
                  break;
                }
              }
              render();
              send(text, type);
            },
            { once: true }
          );
        }
        console.error('[pangi-widget] envío falló:', err);
      });
  }

  // ── Abrir / cerrar ────────────────────────────────────────────────────────
  function setOpen(open) {
    state.open = open;
    el.panel.classList.toggle('pw-open', open);
    el.launcher.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      render();
      el.textarea.focus();
      if (AUTOSTART && !state.messages.length && !state.sending) {
        send('hola', 'text');
      }
    } else {
      el.launcher.focus();
    }
  }

  // ── Focus trap simple dentro del panel ───────────────────────────────────
  function trap(e) {
    if (!state.open || e.key !== 'Tab') return;
    var f = el.panel.querySelectorAll('button, textarea, [href], [tabindex]:not([tabindex="-1"])');
    var list = Array.prototype.filter.call(f, function (n) { return !n.disabled && n.offsetParent !== null; });
    if (!list.length) return;
    var first = list[0], last = list[list.length - 1];
    if (e.shiftKey && root.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && root.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  // ── Eventos ───────────────────────────────────────────────────────────────
  el.launcher.addEventListener('click', function () { setOpen(!state.open); });
  el.close.addEventListener('click', function () { setOpen(false); });

  el.form.addEventListener('submit', function (e) {
    e.preventDefault();
    var v = el.textarea.value;
    el.textarea.value = '';
    el.textarea.style.height = 'auto';
    send(v, 'text');
  });

  el.textarea.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      el.form.requestSubmit ? el.form.requestSubmit() : el.form.dispatchEvent(new Event('submit', { cancelable: true }));
    }
  });
  el.textarea.addEventListener('input', function () {
    el.textarea.style.height = 'auto';
    el.textarea.style.height = Math.min(el.textarea.scrollHeight, 96) + 'px';
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && state.open) setOpen(false);
    trap(e);
  });

  // ── Montaje ───────────────────────────────────────────────────────────────
  function mount() {
    document.body.appendChild(host);
    render();
  }
  if (document.body) mount();
  else document.addEventListener('DOMContentLoaded', mount);
})();
