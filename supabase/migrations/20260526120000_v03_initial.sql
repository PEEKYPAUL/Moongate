-- Moongate v0.3.0 initial schema
-- See docs/v0.3-supabase-design.md for full design rationale.
--
-- This migration:
--   1. Creates printers and enrollment_tokens tables
--   2. Adds indexes
--   3. Enables Row-Level Security with strict policies
--   4. Revokes direct write access from anon/authenticated roles (Edge Functions only)
--   5. Enables pg_cron and schedules daily cleanup
--
-- Idempotent where possible (uses IF NOT EXISTS / CREATE OR REPLACE).
-- Safe to re-run if a partial apply fails.

BEGIN;

-- ============================================================================
-- 1. EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_cron;       -- daily cleanup job

-- ============================================================================
-- 2. TABLES
-- ============================================================================

-- printers: one row per paired Pi
CREATE TABLE IF NOT EXISTS public.printers (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name              text NOT NULL,
  pi_public_key     text NOT NULL,
  tunnel_url_enc    bytea,                                -- AES-GCM ciphertext; NULL until first heartbeat
  tunnel_url_nonce  bytea,                                -- AES-GCM nonce; NULL with tunnel_url_enc
  last_seen         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  revoked_at        timestamptz,
  CONSTRAINT tunnel_url_both_or_neither
    CHECK ((tunnel_url_enc IS NULL) = (tunnel_url_nonce IS NULL))
);

COMMENT ON TABLE public.printers IS
  'Paired printers. tunnel_url_enc is AES-256-GCM ciphertext of the current cloudflared URL; key lives in MOONGATE_TUNNEL_URL_KEY env var on the Edge Functions runtime.';
COMMENT ON COLUMN public.printers.pi_public_key IS
  'Ed25519 public key generated on the Pi at install. Used to verify signed heartbeats.';
COMMENT ON COLUMN public.printers.revoked_at IS
  'Soft delete. Set by MOONGATE_RESET_OWNER. Hard-deleted by cleanup cron after 1 week.';

-- enrollment_tokens: one-shot codes for pairing
CREATE TABLE IF NOT EXISTS public.enrollment_tokens (
  token_hash        bytea PRIMARY KEY,                    -- SHA-256(raw_token); raw token never stored
  pi_public_key     text NOT NULL UNIQUE,
  expires_at        timestamptz NOT NULL,
  used_at           timestamptz,
  used_by_user_id   uuid REFERENCES auth.users(id)
);

COMMENT ON TABLE public.enrollment_tokens IS
  'Pi-generated one-shot pairing codes. Raw token is shown in QR; only its SHA-256 hash is stored.';

-- ============================================================================
-- 3. INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS printers_owner_idx
  ON public.printers (owner_user_id)
  WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS printers_pi_pubkey_unique_idx
  ON public.printers (pi_public_key)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS printers_last_seen_idx
  ON public.printers (last_seen);

CREATE INDEX IF NOT EXISTS enrollment_tokens_expires_idx
  ON public.enrollment_tokens (expires_at);

-- ============================================================================
-- 4. ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.printers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_tokens ENABLE ROW LEVEL SECURITY;

-- printers: users see only their own non-revoked rows
DROP POLICY IF EXISTS "select own printers" ON public.printers;
CREATE POLICY "select own printers"
  ON public.printers FOR SELECT
  TO authenticated
  USING (owner_user_id = auth.uid() AND revoked_at IS NULL);

-- Clients NEVER write directly. Edge Functions do all writes via service role.
REVOKE INSERT, UPDATE, DELETE ON public.printers          FROM anon, authenticated;
REVOKE ALL                    ON public.enrollment_tokens FROM anon, authenticated;

-- ============================================================================
-- 5. CLEANUP CRON
-- ============================================================================

CREATE OR REPLACE FUNCTION public.moongate_cleanup_inactive()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_stale   int;
  deleted_revoked int;
  deleted_tokens  int;
BEGIN
  -- 1. Stale printers (no heartbeat in 6 weeks)
  DELETE FROM public.printers
  WHERE revoked_at IS NULL
    AND (
      (last_seen IS NULL AND created_at < now() - interval '6 weeks')
      OR last_seen < now() - interval '6 weeks'
    );
  GET DIAGNOSTICS deleted_stale = ROW_COUNT;

  -- 2. Old soft-deleted printers (1-week audit window)
  DELETE FROM public.printers
  WHERE revoked_at < now() - interval '1 week';
  GET DIAGNOSTICS deleted_revoked = ROW_COUNT;

  -- 3. Expired enrollment tokens (1-day grace)
  DELETE FROM public.enrollment_tokens
  WHERE expires_at < now() - interval '1 day';
  GET DIAGNOSTICS deleted_tokens = ROW_COUNT;

  RAISE NOTICE 'moongate_cleanup: % stale, % revoked, % tokens',
    deleted_stale, deleted_revoked, deleted_tokens;
END;
$$;

COMMENT ON FUNCTION public.moongate_cleanup_inactive() IS
  'Daily hygiene: prune printers inactive >6w, revoked >1w, expired enrollment tokens >1d.';

-- Schedule daily at 03:15 UTC (idempotent — unschedule if exists, then re-schedule)
DO $$
DECLARE
  job_id bigint;
BEGIN
  SELECT jobid INTO job_id FROM cron.job WHERE jobname = 'moongate-cleanup-inactive';
  IF job_id IS NOT NULL THEN
    PERFORM cron.unschedule(job_id);
  END IF;

  PERFORM cron.schedule(
    'moongate-cleanup-inactive',
    '15 3 * * *',
    $cron$ SELECT public.moongate_cleanup_inactive(); $cron$
  );
END $$;

COMMIT;

-- ============================================================================
-- POST-APPLY VERIFICATION (run these manually to confirm)
-- ============================================================================
--
-- 1. Confirm tables exist:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_schema='public' AND table_name IN ('printers','enrollment_tokens');
--
-- 2. Confirm RLS is enabled:
--    SELECT relname, relrowsecurity FROM pg_class
--    WHERE relname IN ('printers','enrollment_tokens');
--    -- both should show relrowsecurity = true
--
-- 3. Confirm cron job is scheduled:
--    SELECT jobname, schedule, active FROM cron.job WHERE jobname='moongate-cleanup-inactive';
--
-- 4. Dry-run the cleanup on empty tables (should print "0 stale, 0 revoked, 0 tokens"):
--    SET client_min_messages = NOTICE;
--    SELECT public.moongate_cleanup_inactive();
--
-- 5. Verify cross-tenant isolation (requires two anon users — see supabase/README.md §Verifying RLS).
