-- ============================================================
-- PANGI_DEV — Schema Reconciliation v1.2.0
-- Documenta objetos creados en caliente durante el desarrollo
-- del MVP que no quedaron en 01_schema_pangi_dev.sql.
--
-- Verificado contra la DB viva el 2026-08-11.
-- Idempotente: seguro de re-ejecutar.
-- Autor: Erick Del Piero
-- ============================================================

BEGIN;

-- ── 1. MESSAGE_DEDUP ────────────────────────────────────────
-- Guard anti-duplicados del orquestador. Evita que un mismo
-- mensaje se procese dos veces cuando el canal reintenta la
-- entrega (Evolution/Telegram pueden reenviar el mismo update).
--
-- CAVEAT documentado: el dedup por texto puede matar flujos
-- legítimos (ej. el usuario envía "1" para modalidad y luego
-- "1" para selección de doctor). La clave debe incluir un
-- discriminante temporal o de estado, no solo el texto.
CREATE TABLE IF NOT EXISTS message_dedup (
    dedup_key   VARCHAR PRIMARY KEY,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. UNA SESIÓN ACTIVA POR USUARIO ────────────────────────
-- Índice único PARCIAL: garantiza que un usuario tenga como
-- máximo UNA sesión no expirada. Las sesiones expiradas quedan
-- fuera del índice, así que el historial se conserva sin
-- colisionar. Esto es lo que impide sesiones fantasma cuando
-- el usuario reinicia la conversación.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_session_per_user
    ON public.sessions USING btree (user_id)
    WHERE ((state)::text <> 'expired'::text);

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
SELECT 'message_dedup existe:' AS check,
       EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='public' AND table_name='message_dedup') AS ok;

SELECT 'índice sesión única existe:' AS check,
       EXISTS (SELECT 1 FROM pg_indexes
               WHERE indexname='idx_one_active_session_per_user') AS ok;
