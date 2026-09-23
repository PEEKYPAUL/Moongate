-- Moongate - explicit Data API grants on every table.
--
-- Supabase no longer grants Data API access to NEW tables in public
-- automatically (new projects since 2026-05-30, existing projects from
-- 2026-10-30). Existing tables keep whatever they already hold, so the live
-- project is unaffected. But every earlier migration in this directory relied
-- on those automatic grants (they only REVOKE), which means a rebuild from this
-- directory after that date - a new project, a preview branch, a local
-- `supabase db reset` - would come up with tables that neither the Edge
-- Functions nor the app can reach ("permission denied", even where RLS would
-- allow the row). This migration states the grants explicitly so the schema is
-- self-sufficient, and it tidies the leftovers the old defaults left behind.
--
-- Effective posture (read off the live project on 2026-09-23 before this ran):
--   • service_role  - SELECT/INSERT/UPDATE/DELETE on every table. Used only by
--                     the Edge Functions. send-push, register-push-token,
--                     submit-feedback and read-feedback touch tables directly;
--                     everything else goes through the SECURITY DEFINER RPCs,
--                     whose EXECUTE grants are already explicit
--                     (20260619170000_lock_rpc_execute_to_service_role).
--   • authenticated - SELECT on printers only. The app always holds an
--                     anonymous SESSION, which is this role; rows are filtered
--                     by the "select own printers" policy (v03_initial).
--   • anon          - nothing. The bare anon role never reads a table. It held
--                     SELECT on printers from the old defaults (zero rows under
--                     RLS); revoked here.
--   • TRUNCATE / REFERENCES / TRIGGER, which the old defaults handed to every
--     role, are revoked: PostgREST never exposes them and nothing should hold
--     what it does not use.
--
-- No sequences: every primary key is a uuid, so the sequence half of the
-- Supabase change does not apply here.
--
-- RULE for every future table (Supabase's own guidance - treat as ONE unit in
-- the migration that creates it): GRANT the roles that need it, ENABLE ROW
-- LEVEL SECURITY, then the policies. Section 3.5 of supabase/README.md has the
-- verify query.
--
-- Idempotent. Safe to re-run (GRANT and REVOKE are).

BEGIN;

-- Schema usage: every Supabase project already grants this to all three roles
-- and the change does not touch it; restated so a rebuild does not depend on it.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ============================================================================
-- 1. EDGE FUNCTIONS (service role): full DML on every table, nothing more
-- ============================================================================

REVOKE ALL ON TABLE
  public.printers,
  public.enrollment_tokens,
  public.feedback,
  public.restore_grants,
  public.device_push_tokens
FROM service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.printers,
  public.enrollment_tokens,
  public.feedback,
  public.restore_grants,
  public.device_push_tokens
TO service_role;

-- ============================================================================
-- 2. APP (anonymous session = authenticated role): read its own printers
-- ============================================================================

REVOKE ALL ON TABLE public.printers FROM anon, authenticated;
GRANT SELECT ON TABLE public.printers TO authenticated;

-- ============================================================================
-- 3. EVERYTHING ELSE stays closed to clients (restates the earlier REVOKEs so
--    this one file documents the whole posture)
-- ============================================================================

REVOKE ALL ON TABLE
  public.enrollment_tokens,
  public.feedback,
  public.restore_grants,
  public.device_push_tokens
FROM anon, authenticated;

COMMIT;

-- ============================================================================
-- VERIFY (SQL Editor) - expect exactly these six rows, nothing for anon:
--
--   device_push_tokens | service_role  | DELETE,INSERT,SELECT,UPDATE
--   enrollment_tokens  | service_role  | DELETE,INSERT,SELECT,UPDATE
--   feedback           | service_role  | DELETE,INSERT,SELECT,UPDATE
--   printers           | authenticated | SELECT
--   printers           | service_role  | DELETE,INSERT,SELECT,UPDATE
--   restore_grants     | service_role  | DELETE,INSERT,SELECT,UPDATE
--
-- SELECT table_name, grantee,
--        string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public'
--   AND grantee IN ('anon', 'authenticated', 'service_role')
-- GROUP BY table_name, grantee
-- ORDER BY table_name, grantee;
-- ============================================================================
