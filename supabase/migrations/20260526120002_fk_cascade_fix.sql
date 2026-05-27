-- Moongate v0.3.0 — FK cascade fix
--
-- The initial migration created enrollment_tokens.used_by_user_id with a
-- default-RESTRICT foreign key to auth.users. That blocks user deletion as
-- soon as the user has redeemed an enrollment token — which is the common
-- case (every paired printer leaves a `used` token row behind for ~1 day
-- until the cleanup cron sweeps it).
--
-- Fix: switch the FK to ON DELETE CASCADE so deleting an auth user also
-- removes their used enrollment_tokens. This matches printers.owner_user_id
-- behaviour and is consistent with the §16 cleanup policy (a user being
-- deleted means all their associated data should go too).

BEGIN;

ALTER TABLE public.enrollment_tokens
  DROP CONSTRAINT IF EXISTS enrollment_tokens_used_by_user_id_fkey;

ALTER TABLE public.enrollment_tokens
  ADD CONSTRAINT enrollment_tokens_used_by_user_id_fkey
    FOREIGN KEY (used_by_user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

COMMIT;

-- Verification:
--   SELECT conname, confdeltype FROM pg_constraint
--   WHERE conname = 'enrollment_tokens_used_by_user_id_fkey';
--   -- confdeltype should be 'c' (CASCADE), not 'a' (NO ACTION) or 'r' (RESTRICT)
